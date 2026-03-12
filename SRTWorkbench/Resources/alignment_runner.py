#!/usr/bin/env python3
"""
Alignment runner for SRT Workbench macOS app.

Reads a JSON config from stdin, runs CTC forced alignment, and outputs
progress + results as JSON lines to stdout.

Input JSON:
{
    "audio_path": "/path/to/audio.wav",
    "script_lines": ["Line one", "Line two", ...],
    "output_path": "/path/to/output.srt",
    "model_path": "/path/to/model.onnx"
}

Output JSON lines:
{"type": "progress", "stage": "...", "percent": 0-100}
{"type": "result", "srt_path": "...", "num_cues": N}
{"type": "error", "message": "..."}
"""

import json
import os
import re
import sys


def progress(stage, percent=0):
    """Send a progress update to the Swift app via stdout."""
    msg = {"type": "progress", "stage": stage, "percent": percent}
    print(json.dumps(msg), flush=True)


def error(message):
    """Send an error to the Swift app via stdout."""
    msg = {"type": "error", "message": message}
    print(json.dumps(msg), flush=True)
    sys.exit(1)


def result(srt_path, num_cues):
    """Send the final result to the Swift app via stdout."""
    msg = {"type": "result", "srt_path": srt_path, "num_cues": num_cues}
    print(json.dumps(msg), flush=True)


def format_srt_time(seconds):
    """Convert seconds to SRT timestamp format HH:MM:SS,mmm."""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int(round((seconds - int(seconds)) * 1000))
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def extract_script_lines(docx_path):
    """Extract spoken lines from a .docx script file using python-docx.

    Filters out empty paragraphs and stage directions in [square brackets].
    """
    from docx import Document

    doc = Document(docx_path)
    lines = []
    for para in doc.paragraphs:
        text = para.text.strip()
        if not text:
            continue
        if re.match(r"^\[.*\]$", text):
            continue
        lines.append(text)
    return lines


def main():
    # Read input from stdin
    try:
        raw = sys.stdin.read()
        config = json.loads(raw)
    except Exception as e:
        error(f"Failed to parse input: {e}")

    audio_path = config.get("audio_path")
    docx_path = config.get("docx_path")
    output_path = config.get("output_path")
    model_path = config.get("model_path")

    if not audio_path or not output_path:
        error("Missing audio_path or output_path")

    # Parse .docx to extract script lines
    if docx_path:
        if not os.path.isfile(docx_path):
            error(f"Script file not found: {docx_path}")
        try:
            script_lines = extract_script_lines(docx_path)
        except Exception as e:
            error(f"Failed to parse .docx: {e}")
    else:
        script_lines = config.get("script_lines", [])

    if not script_lines:
        error("No spoken lines found in the script")

    if not os.path.isfile(audio_path):
        error(f"Audio file not found: {audio_path}")

    # Set model path for ctc_forced_aligner if provided
    if model_path:
        model_dir = os.path.dirname(model_path)
        os.makedirs(model_dir, exist_ok=True)
        # The AlignmentSingleton looks for the model at ~/ctc_forced_aligner/model.onnx
        # We symlink our model location if needed
        default_model_dir = os.path.expanduser("~/ctc_forced_aligner")
        default_model_path = os.path.join(default_model_dir, "model.onnx")
        if os.path.isfile(model_path) and not os.path.isfile(default_model_path):
            os.makedirs(default_model_dir, exist_ok=True)
            try:
                os.symlink(model_path, default_model_path)
            except OSError:
                pass  # May already exist or permission issue

    # Import alignment libraries
    progress("Importing alignment libraries...", 5)
    try:
        from ctc_forced_aligner import (
            AlignmentSingleton,
            generate_emissions,
            get_alignments,
            get_spans,
            load_audio,
            postprocess_results,
            preprocess_text,
        )
    except ImportError as e:
        error(f"Failed to import ctc_forced_aligner: {e}")

    # Run alignment pipeline
    full_text = " ".join(script_lines)

    progress("Loading alignment model...", 10)
    try:
        aligner = AlignmentSingleton()
    except Exception as e:
        error(f"Failed to load alignment model: {e}")

    progress("Loading audio...", 20)
    try:
        audio_waveform = load_audio(audio_path)
    except Exception as e:
        error(f"Failed to load audio: {e}")

    progress("Generating emissions...", 30)
    try:
        emissions, stride = generate_emissions(
            aligner.alignment_model, audio_waveform, batch_size=16
        )
    except Exception as e:
        error(f"Failed to generate emissions: {e}")

    progress("Preprocessing text...", 50)
    try:
        tokens_starred, text_starred = preprocess_text(
            full_text, romanize=True, language="eng"
        )
    except Exception as e:
        error(f"Failed to preprocess text: {e}")

    progress("Running CTC forced alignment...", 60)
    try:
        segments, scores, blank_token = get_alignments(
            emissions, tokens_starred, aligner.alignment_tokenizer
        )
    except Exception as e:
        error(f"Failed to run alignment: {e}")

    progress("Post-processing results...", 80)
    try:
        spans = get_spans(tokens_starred, segments, blank_token)
        word_timestamps = postprocess_results(text_starred, spans, stride, scores)
    except Exception as e:
        error(f"Failed to post-process: {e}")

    progress("Generating SRT file...", 90)

    # Map word-level timestamps back to original script lines
    MAX_SUBTITLE_SECS = 4.5
    srt_entries = []
    word_idx = 0
    total_words = len(word_timestamps)

    for line in script_lines:
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
                seg_start_i = 0
                for wi in range(1, len(line_word_ts)):
                    seg_begin = line_word_ts[seg_start_i]["start"]
                    seg_end = line_word_ts[wi]["end"]
                    if seg_end - seg_begin > MAX_SUBTITLE_SECS:
                        seg_text = " ".join(line_words[seg_start_i:wi])
                        srt_entries.append((
                            line_word_ts[seg_start_i]["start"],
                            line_word_ts[wi - 1]["end"],
                            seg_text,
                        ))
                        seg_start_i = wi
                if seg_start_i < len(line_word_ts):
                    seg_text = " ".join(line_words[seg_start_i:])
                    srt_entries.append((
                        line_word_ts[seg_start_i]["start"],
                        line_word_ts[-1]["end"],
                        seg_text,
                    ))

        word_idx = end_idx

    # Enforce minimum subtitle duration of 1 second
    MIN_SUBTITLE_SECS = 1.0
    for i in range(len(srt_entries)):
        begin, end, text = srt_entries[i]
        if end - begin < MIN_SUBTITLE_SECS:
            new_end = begin + MIN_SUBTITLE_SECS
            # Don't overlap into the next cue
            if i + 1 < len(srt_entries):
                next_begin = srt_entries[i + 1][0]
                new_end = min(new_end, next_begin)
            srt_entries[i] = (begin, new_end, text)

    # Write SRT file
    try:
        with open(output_path, "w", encoding="utf-8") as f:
            for i, (begin, end, text) in enumerate(srt_entries, 1):
                f.write(f"{i}\n")
                f.write(f"{format_srt_time(begin)} --> {format_srt_time(end)}\n")
                f.write(f"{text}\n")
                f.write("\n")
    except Exception as e:
        error(f"Failed to write SRT file: {e}")

    progress("Complete", 100)
    result(output_path, len(srt_entries))


if __name__ == "__main__":
    main()
