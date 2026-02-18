#!/usr/bin/env python3
"""
SRT Generator — Forced alignment of a video's audio against a ground-truth script.

Uses CTC forced alignment (wav2vec2 via ONNX) for accurate timing of ground-truth
text against audio, producing SRT subtitle files.

Usage:
    python generate_srt.py <video_file> <script_docx> [output_srt]

Requires:
    - ffmpeg (for audio extraction)
    - Python packages: ctc-forced-aligner, python-docx (install in the .venv)
"""

import os
import re
import shutil
import sys
import subprocess
import tempfile

from docx import Document
from ctc_forced_aligner import (
    AlignmentSingleton,
    generate_emissions,
    get_alignments,
    get_spans,
    load_audio,
    postprocess_results,
    preprocess_text,
)


def extract_script_lines(docx_path):
    """Extract spoken lines from a .docx script file.

    Filters out:
    - Empty paragraphs
    - Stage directions in [square brackets]
    """
    doc = Document(docx_path)
    lines = []
    for para in doc.paragraphs:
        text = para.text.strip()
        if not text:
            continue
        # Skip stage directions like [Cut to dramatic music...]
        if re.match(r"^\[.*\]$", text):
            continue
        lines.append(text)
    return lines


def extract_audio_wav(video_path, audio_path):
    """Extract audio from a video file as mono 16kHz WAV."""
    ffmpeg_bin = os.environ.get("FFMPEG_BIN") or shutil.which("ffmpeg")
    if not ffmpeg_bin:
        print(
            "Error: ffmpeg was not found. Set FFMPEG_BIN or install ffmpeg.",
            file=sys.stderr,
        )
        sys.exit(1)

    cmd = [
        ffmpeg_bin, "-y",
        "-i", video_path,
        "-vn",
        "-acodec", "pcm_s16le",
        "-ar", "16000",
        "-ac", "1",
        audio_path,
    ]
    print(f"Extracting audio from: {os.path.basename(video_path)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ffmpeg error:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)


def format_srt_time(seconds):
    """Convert seconds to SRT timestamp format HH:MM:SS,mmm."""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int(round((seconds - int(seconds)) * 1000))
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def align_and_generate_srt(audio_path, lines, srt_path):
    """Run CTC forced alignment on audio+text and write SRT.

    Uses word-level alignment then maps words back to original script lines.
    """
    # Combine all lines into full text for alignment
    full_text = " ".join(lines)

    print("Loading alignment model (ONNX, first run downloads ~1.2GB)...")
    aligner = AlignmentSingleton()

    print("Loading audio...")
    audio_waveform = load_audio(audio_path)

    print("Generating emissions...")
    emissions, stride = generate_emissions(
        aligner.alignment_model, audio_waveform, batch_size=16
    )

    print("Preprocessing text...")
    tokens_starred, text_starred = preprocess_text(
        full_text, romanize=True, language="eng"
    )

    print("Running CTC forced alignment...")
    segments, scores, blank_token = get_alignments(
        emissions, tokens_starred, aligner.alignment_tokenizer
    )

    spans = get_spans(tokens_starred, segments, blank_token)
    word_timestamps = postprocess_results(text_starred, spans, stride, scores)

    print(f"  Aligned {len(word_timestamps)} words")

    # Map word-level timestamps back to original script lines,
    # then split any entries longer than MAX_SUBTITLE_SECS into
    # shorter segments using the per-word timestamps.
    MAX_SUBTITLE_SECS = 4.5

    srt_entries = []
    word_idx = 0
    total_words = len(word_timestamps)

    for line in lines:
        line_words = line.split()
        n_words = len(line_words)

        if word_idx >= total_words:
            break

        end_idx = min(word_idx + n_words, total_words)
        line_word_ts = word_timestamps[word_idx:end_idx]

        if line_word_ts:
            begin = line_word_ts[0]["start"]
            end = line_word_ts[-1]["end"]
            duration = end - begin

            if duration <= MAX_SUBTITLE_SECS:
                srt_entries.append((begin, end, line))
            else:
                # Split into segments using actual word timestamps.
                # Walk through words, starting a new segment whenever
                # the current one would exceed MAX_SUBTITLE_SECS.
                seg_start_i = 0
                for wi in range(1, len(line_word_ts)):
                    seg_begin = line_word_ts[seg_start_i]["start"]
                    seg_end = line_word_ts[wi]["end"]
                    if seg_end - seg_begin > MAX_SUBTITLE_SECS:
                        # Finish the current segment up to the previous word
                        seg_text = " ".join(line_words[seg_start_i:wi])
                        srt_entries.append((
                            line_word_ts[seg_start_i]["start"],
                            line_word_ts[wi - 1]["end"],
                            seg_text,
                        ))
                        seg_start_i = wi
                # Final segment
                if seg_start_i < len(line_word_ts):
                    seg_text = " ".join(line_words[seg_start_i:])
                    srt_entries.append((
                        line_word_ts[seg_start_i]["start"],
                        line_word_ts[-1]["end"],
                        seg_text,
                    ))

        word_idx = end_idx

    # Write SRT file
    with open(srt_path, "w", encoding="utf-8") as f:
        for i, (begin, end, text) in enumerate(srt_entries, 1):
            f.write(f"{i}\n")
            f.write(f"{format_srt_time(begin)} --> {format_srt_time(end)}\n")
            f.write(f"{text}\n")
            f.write("\n")

    print(f"SRT file generated: {srt_path}")
    print(f"  {len(srt_entries)} subtitle entries")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    video_path = sys.argv[1]
    docx_path = sys.argv[2]

    if len(sys.argv) >= 4:
        srt_path = sys.argv[3]
    else:
        base = os.path.splitext(video_path)[0]
        srt_path = base + ".srt"

    if not os.path.isfile(video_path):
        print(f"Error: Video file not found: {video_path}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(docx_path):
        print(f"Error: Script file not found: {docx_path}", file=sys.stderr)
        sys.exit(1)

    # Step 1: Extract script lines from .docx
    print(f"Reading script from: {os.path.basename(docx_path)}")
    lines = extract_script_lines(docx_path)
    print(f"  Found {len(lines)} spoken lines")

    with tempfile.TemporaryDirectory() as tmpdir:
        # Step 2: Extract audio from video
        audio_path = os.path.join(tmpdir, "audio.wav")
        extract_audio_wav(video_path, audio_path)

        # Step 3: Run CTC forced alignment and generate SRT
        align_and_generate_srt(audio_path, lines, srt_path)

    print("\nDone!")


if __name__ == "__main__":
    main()
