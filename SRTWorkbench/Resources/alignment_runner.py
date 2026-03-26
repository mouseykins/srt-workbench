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


def section_match(matched, heading):
    """Report whether a document section was matched to the video."""
    msg = {"type": "section_match", "matched": matched, "heading": heading}
    print(json.dumps(msg), flush=True)


def format_srt_time(seconds):
    """Convert seconds to SRT timestamp format HH:MM:SS,mmm."""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int(round((seconds - int(seconds)) * 1000))
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def _compile_filters(filter_patterns):
    """Compile a list of regex pattern strings, reporting invalid ones as errors."""
    compiled = []
    for p in (filter_patterns or []):
        try:
            compiled.append(re.compile(p))
        except re.error as e:
            error(f"Invalid filter regex '{p}': {e}")
    return compiled


def _is_spoken_line(text, filters=None):
    """Return True if the line is non-empty spoken text that doesn't match any filter."""
    if not text:
        return False
    if filters:
        for pattern in filters:
            if pattern.match(text):
                return False
    return True


def _apply_strip_patterns(text, strips):
    """Remove all inline matches of strip patterns from text."""
    for pattern in strips:
        text = pattern.sub("", text)
    # Collapse multiple spaces and re-strip
    text = re.sub(r"  +", " ", text).strip()
    return text


def extract_script_lines(docx_path, filter_patterns=None, strip_patterns=None):
    """Extract spoken lines from a .docx script file using python-docx.

    First strips inline patterns (e.g. slide numbers), then filters out
    empty paragraphs and lines matching any of the provided filter patterns.
    """
    from docx import Document

    filters = _compile_filters(filter_patterns)
    strips = _compile_filters(strip_patterns)
    doc = Document(docx_path)
    lines = []
    for para in doc.paragraphs:
        text = para.text.strip()
        if strips:
            text = _apply_strip_patterns(text, strips)
        if _is_spoken_line(text, filters):
            lines.append(text)
    return lines


def _normalize_identifier(s):
    """Normalize a string for fuzzy matching: lowercase, collapse separators."""
    s = s.lower()
    s = re.sub(r"[._\-\s]+", " ", s)
    return s.strip()


def _extract_leading_id(s):
    """Extract leading identifier like '1.2.1', '3a', 'Ch3' from a string."""
    m = re.match(r"^\s*([A-Za-z]*\d[\d.]*[A-Za-z]?)", s)
    return m.group(1).lower() if m else None


def _find_matching_section(sections, video_stem):
    """Find the section whose heading matches the video filename stem.

    Returns (heading_text, lines) tuple or (None, None) if no match.
    """
    stem_norm = _normalize_identifier(video_stem)

    # Strategy 1: normalized stem is a substring of heading or vice versa
    for heading, lines in sections:
        heading_norm = _normalize_identifier(heading)
        if stem_norm in heading_norm or heading_norm in stem_norm:
            return heading, lines

    # Strategy 2: compare leading numeric/alphanumeric identifiers
    stem_id = _extract_leading_id(video_stem)
    if stem_id:
        for heading, lines in sections:
            heading_id = _extract_leading_id(heading)
            if heading_id and stem_id == heading_id:
                return heading, lines

    return None, None


def _is_section_heading(style_name, text):
    """Detect whether a paragraph is a section heading.

    Checks Word heading styles first, then falls back to detecting text
    patterns like '1.2.1 – Title', 'Ch3 - Title', 'A2: Title', etc.
    """
    if style_name.startswith("Heading"):
        return True
    # Text pattern: dotted identifier like '1.2.1' or letter-prefixed like 'Ch3'
    # followed by a separator (dash, en-dash, em-dash, colon, pipe) and a title.
    # Requires either a dot in the identifier or a letter prefix to avoid
    # matching slide numbers like '1:' or '2:'.
    if re.match(r"^[A-Za-z]+\d[\d.]*[A-Za-z]?\s*[–\-—:|]", text):
        return True
    if re.match(r"^[A-Za-z]*\d[\d.]*[A-Za-z]?\s*[–\-—:|]", text) and "." in text.split()[0]:
        return True
    return False


def extract_section_lines(docx_path, video_stem, filter_patterns=None, strip_patterns=None):
    """Extract spoken lines for a specific section of a multi-section .docx.

    Splits the document on section headings (detected by Word heading styles
    or text patterns like '1.2.1 – Title'), then matches the video filename
    stem against heading text. Returns (heading, lines) if matched, or
    (None, None) if no headings exist or no match is found.
    """
    from docx import Document

    filters = _compile_filters(filter_patterns)
    strips = _compile_filters(strip_patterns)
    doc = Document(docx_path)
    sections = []  # list of (heading_text, [lines])
    current_heading = None
    current_lines = []

    for para in doc.paragraphs:
        style_name = para.style.name or ""
        text = para.text.strip()

        if text and _is_section_heading(style_name, text):
            # Save previous section
            if current_heading is not None:
                sections.append((current_heading, current_lines))
            current_heading = text
            current_lines = []
        else:
            if strips:
                text = _apply_strip_patterns(text, strips)
            if _is_spoken_line(text, filters):
                current_lines.append(text)

    # Capture the last section
    if current_heading is not None:
        sections.append((current_heading, current_lines))

    if not sections:
        return None, None

    return _find_matching_section(sections, video_stem)


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
    video_stem = config.get("video_stem")
    filter_patterns = config.get("filter_patterns", [r"^\[.*\]$"])
    strip_patterns = config.get("strip_patterns", [])

    if not audio_path or not output_path:
        error("Missing audio_path or output_path")

    # Parse .docx to extract script lines
    if docx_path:
        if not os.path.isfile(docx_path):
            error(f"Script file not found: {docx_path}")
        try:
            # Try section-based extraction if we have a video stem
            if video_stem:
                matched_heading, section_lines = extract_section_lines(
                    docx_path, video_stem, filter_patterns=filter_patterns, strip_patterns=strip_patterns
                )
                if section_lines is not None:
                    script_lines = section_lines
                    section_match(True, matched_heading)
                else:
                    script_lines = extract_script_lines(docx_path, filter_patterns=filter_patterns, strip_patterns=strip_patterns)
                    section_match(False, None)
            else:
                script_lines = extract_script_lines(docx_path, filter_patterns=filter_patterns, strip_patterns=strip_patterns)
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
