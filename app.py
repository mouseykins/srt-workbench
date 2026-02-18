from __future__ import annotations

import os
import re
import subprocess
import traceback
import uuid
from pathlib import Path
from typing import Iterable

from flask import (
    Flask,
    Response,
    abort,
    flash,
    jsonify,
    redirect,
    render_template,
    request,
    send_file,
    session,
    url_for,
)
from werkzeug.utils import secure_filename

from generate_srt import align_and_generate_srt, extract_audio_wav, extract_script_lines

ROOT = Path(__file__).resolve().parent
ASSETS_DIR = ROOT / "assets"
MEDIA_DIR = ROOT / "media"
UPLOADS_DIR = ROOT / "uploads"
DEFAULT_MEDIA_DIR = MEDIA_DIR

ALLOWED_VIDEO_EXTS = {".mp4", ".mov", ".mkv", ".webm", ".m4v"}
ALLOWED_SCRIPT_EXTS = {".docx"}
ALLOWED_SRT_EXTS = {".srt"}

TIMECODE_RE = re.compile(r"^\d{2}:\d{2}:\d{2},\d{3}$")
CUE_TIMING_RE = re.compile(
    r"^(\d{2}:\d{2}:\d{2}[,.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,.]\d{3})$"
)

app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "dev-only-secret-change-me")


def _ensure_dirs() -> None:
    ASSETS_DIR.mkdir(exist_ok=True)
    MEDIA_DIR.mkdir(parents=True, exist_ok=True)
    UPLOADS_DIR.mkdir(exist_ok=True)


def _is_within(path: Path, base: Path) -> bool:
    try:
        path.resolve().relative_to(base.resolve())
        return True
    except ValueError:
        return False


def _resolve_media_dir(raw_value: str | None) -> tuple[Path, bool]:
    raw = (raw_value or "").strip()
    if not raw:
        return DEFAULT_MEDIA_DIR.resolve(), False

    candidate = Path(raw).expanduser()
    if candidate.exists() and candidate.is_dir():
        return candidate.resolve(), False

    return DEFAULT_MEDIA_DIR.resolve(), True


def _get_active_media_dir(raw_value: str | None) -> tuple[Path, bool]:
    requested = (raw_value or "").strip()
    if not requested:
        requested = (session.get("media_dir") or "").strip()
    media_dir, invalid = _resolve_media_dir(requested)
    session["media_dir"] = str(media_dir)
    return media_dir, invalid


def _open_directory_picker(initial_dir: str) -> tuple[str | None, str | None]:
    preferred_path = Path(initial_dir).expanduser() if initial_dir else DEFAULT_MEDIA_DIR
    if not preferred_path.exists() or not preferred_path.is_dir():
        preferred_path = DEFAULT_MEDIA_DIR
    preferred = str(preferred_path.resolve())

    # Use macOS native folder picker via AppleScript.
    script = (
        'set defaultFolder to POSIX file "{}"\n'
        'set chosenFolder to choose folder with prompt "Select media base directory" '
        "default location defaultFolder\n"
        "return POSIX path of chosenFolder"
    ).format(preferred.replace('"', '\\"'))
    try:
        proc = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode == 0:
            picked = proc.stdout.strip()
            if picked:
                return picked, None
            return None, "No directory selected."

        err = (proc.stderr or "").strip()
        if "User canceled" in err:
            return None, "No directory selected."
        return None, f"Directory picker failed: {err or 'unknown error'}"
    except Exception as exc:
        return None, f"Directory picker failed: {exc}"


def _iter_files(paths: Iterable[Path], exts: set[str]) -> list[Path]:
    files: list[Path] = []
    seen: set[Path] = set()

    for base in paths:
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if p.is_file() and p.suffix.lower() in exts:
                resolved = p.resolve()
                if resolved in seen:
                    continue
                seen.add(resolved)
                files.append(resolved)

    return sorted(files)


def _path_from_form_value(raw_path: str, allowed_exts: set[str], allowed_dirs: list[Path]) -> Path:
    candidate = Path(raw_path).expanduser().resolve()

    if candidate.suffix.lower() not in allowed_exts:
        raise ValueError("Unexpected file type")

    if not candidate.exists() or not candidate.is_file():
        raise ValueError("File not found")

    if not any(_is_within(candidate, d) for d in allowed_dirs):
        raise ValueError("File is outside allowed directories")

    return candidate


def _save_upload(file_obj, allowed_exts: set[str]) -> Path | None:
    if not file_obj or not file_obj.filename:
        return None

    safe_name = secure_filename(file_obj.filename)
    ext = Path(safe_name).suffix.lower()
    if ext not in allowed_exts:
        raise ValueError(f"Unsupported file extension: {ext}")

    unique = f"{uuid.uuid4().hex[:8]}-{safe_name}"
    out_path = UPLOADS_DIR / unique
    file_obj.save(out_path)
    return out_path.resolve()


def _timecode_to_seconds(value: str) -> float:
    if not TIMECODE_RE.fullmatch(value):
        raise ValueError(f"Invalid SRT timecode: {value}")

    hh = int(value[0:2])
    mm = int(value[3:5])
    ss = int(value[6:8])
    ms = int(value[9:12])
    return hh * 3600 + mm * 60 + ss + (ms / 1000.0)


def _parse_srt_text(srt_text: str) -> list[dict[str, str]]:
    normalized = srt_text.replace("\r\n", "\n").replace("\r", "\n")
    blocks = [b for b in re.split(r"\n\s*\n", normalized.strip()) if b.strip()]

    cues: list[dict[str, str]] = []
    for block in blocks:
        lines = [line.rstrip() for line in block.split("\n") if line.strip() != ""]
        if not lines:
            continue

        timing_line = lines[1] if len(lines) >= 2 and "-->" in lines[1] else lines[0]
        m = CUE_TIMING_RE.match(timing_line.strip())
        if not m:
            continue

        start = m.group(1).replace(".", ",")
        end = m.group(2).replace(".", ",")
        text_start = 2 if timing_line == (lines[1] if len(lines) >= 2 else None) else 1
        text = "\n".join(lines[text_start:]).strip()

        cues.append({"start": start, "end": end, "text": text})

    return cues


def _cue_to_seconds(cue: dict[str, str]) -> tuple[float, float]:
    start = _timecode_to_seconds(cue["start"])
    end = _timecode_to_seconds(cue["end"])
    return start, end


def _serialize_srt(cues: list[dict[str, str]]) -> str:
    out: list[str] = []
    for idx, cue in enumerate(cues, start=1):
        text = (cue.get("text") or "").strip()
        out.append(str(idx))
        out.append(f"{cue['start']} --> {cue['end']}")
        out.append(text)
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def _to_vtt_text(srt_text: str) -> str:
    lines = srt_text.splitlines()
    out: list[str] = ["WEBVTT", ""]

    timestamp_line = re.compile(r"^\d{2}:\d{2}:\d{2},\d{3}\s+-->\s+\d{2}:\d{2}:\d{2},\d{3}")
    for line in lines:
        if timestamp_line.match(line.strip()):
            out.append(line.replace(",", "."))
        else:
            out.append(line)

    return "\n".join(out) + "\n"


def _file_options(files: list[Path]) -> list[dict[str, str]]:
    return [{"path": str(p), "name": p.name} for p in files]


@app.route("/")
def index():
    _ensure_dirs()

    media_dir, invalid_dir = _get_active_media_dir(request.args.get("media_dir"))
    if invalid_dir:
        flash("Selected media directory was not found. Reverted to default media directory.", "error")

    videos = _iter_files([media_dir, UPLOADS_DIR], ALLOWED_VIDEO_EXTS)
    scripts = _iter_files([media_dir, UPLOADS_DIR], ALLOWED_SCRIPT_EXTS)
    srts = _iter_files([media_dir, UPLOADS_DIR], ALLOWED_SRT_EXTS)

    return render_template(
        "index.html",
        videos=_file_options(videos),
        scripts=_file_options(scripts),
        srts=_file_options(srts),
        media_dir=str(media_dir),
        active_page="generate",
    )


@app.post("/generate")
def generate():
    _ensure_dirs()

    try:
        media_dir_raw = request.form.get("media_dir", "")
        media_dir, invalid_dir = _get_active_media_dir(media_dir_raw)
        if invalid_dir:
            raise ValueError("Media directory not found")

        allowed_dirs = [media_dir, UPLOADS_DIR]

        chosen_video_path = request.form.get("video_path", "").strip()
        chosen_script_path = request.form.get("script_path", "").strip()

        video_file = _save_upload(request.files.get("video_upload"), ALLOWED_VIDEO_EXTS)
        script_file = _save_upload(request.files.get("script_upload"), ALLOWED_SCRIPT_EXTS)

        if video_file is None:
            if not chosen_video_path:
                raise ValueError("Select a video or upload one.")
            video_file = _path_from_form_value(chosen_video_path, ALLOWED_VIDEO_EXTS, allowed_dirs)

        if script_file is None:
            if not chosen_script_path:
                raise ValueError("Select a script or upload one.")
            script_file = _path_from_form_value(chosen_script_path, ALLOWED_SCRIPT_EXTS, allowed_dirs)

        out_name = f"{video_file.stem} - aligned.srt"
        out_path = (UPLOADS_DIR / out_name).resolve()

        lines = extract_script_lines(str(script_file))
        if not lines:
            raise ValueError("The selected script has no spoken lines after filtering.")

        tmp_wav = UPLOADS_DIR / f"tmp-{uuid.uuid4().hex}.wav"
        try:
            extract_audio_wav(str(video_file), str(tmp_wav))
            align_and_generate_srt(str(tmp_wav), lines, str(out_path))
        finally:
            if tmp_wav.exists():
                tmp_wav.unlink()

        flash(f"Generated SRT: {out_path.name}", "success")
        return redirect(
            url_for(
                "review",
                video_path=str(video_file),
                srt_path=str(out_path),
                media_dir=str(media_dir),
            )
        )

    except Exception as exc:
        flash(f"Generation failed: {exc}", "error")
        app.logger.error(traceback.format_exc())
        return redirect(url_for("index", media_dir=request.form.get("media_dir", "")))


@app.post("/pick-directory")
def pick_directory():
    current_media_dir = request.form.get("media_dir", "")
    return_to = request.form.get("return_to", "index")
    video_path = request.form.get("video_path", "")
    srt_path = request.form.get("srt_path", "")

    selected, error = _open_directory_picker(current_media_dir)
    if not selected:
        if error and error != "No directory selected.":
            flash(error, "error")
        selected = current_media_dir

    if return_to == "review":
        return redirect(url_for("review", media_dir=selected, video_path=video_path, srt_path=srt_path))
    return redirect(url_for("index", media_dir=selected))


@app.get("/review")
def review():
    _ensure_dirs()

    media_dir, invalid_dir = _get_active_media_dir(request.args.get("media_dir"))
    if invalid_dir:
        flash("Selected media directory was not found. Reverted to default media directory.", "error")

    videos = _iter_files([media_dir, UPLOADS_DIR], ALLOWED_VIDEO_EXTS)
    srts = _iter_files([media_dir, UPLOADS_DIR], ALLOWED_SRT_EXTS)

    selected_video = request.args.get("video_path", "").strip()
    selected_srt = request.args.get("srt_path", "").strip()

    if videos and not selected_video:
        selected_video = str(videos[0])
    if srts and not selected_srt:
        selected_srt = str(srts[0])

    allowed_dirs = [media_dir, UPLOADS_DIR]

    cues_data: list[dict[str, str]] = []
    selected_srt_name = ""
    if selected_srt:
        try:
            srt_path = _path_from_form_value(selected_srt, ALLOWED_SRT_EXTS, allowed_dirs)
            cues_data = _parse_srt_text(srt_path.read_text(encoding="utf-8", errors="replace"))
            selected_srt_name = srt_path.name
            selected_srt = str(srt_path)
        except ValueError:
            selected_srt = ""

    if selected_video:
        try:
            selected_video = str(_path_from_form_value(selected_video, ALLOWED_VIDEO_EXTS, allowed_dirs))
        except ValueError:
            selected_video = ""

    return render_template(
        "player.html",
        videos=_file_options(videos),
        srts=_file_options(srts),
        selected_video=selected_video,
        selected_srt=selected_srt,
        selected_srt_name=selected_srt_name,
        cues_data=cues_data,
        media_dir=str(media_dir),
        active_page="review",
    )


@app.get("/media")
def media():
    media_dir, _ = _get_active_media_dir(request.args.get("media_dir"))
    allowed_dirs = [media_dir, UPLOADS_DIR]
    raw_file = request.args.get("file", "")

    try:
        p = _path_from_form_value(raw_file, ALLOWED_VIDEO_EXTS, allowed_dirs)
    except ValueError:
        abort(404)

    return send_file(p)


@app.get("/captions.vtt")
def captions():
    media_dir, _ = _get_active_media_dir(request.args.get("media_dir"))
    allowed_dirs = [media_dir, UPLOADS_DIR]
    raw_file = request.args.get("file", "")

    try:
        p = _path_from_form_value(raw_file, ALLOWED_SRT_EXTS, allowed_dirs)
    except ValueError:
        abort(404)

    srt_text = p.read_text(encoding="utf-8", errors="replace")
    vtt_text = _to_vtt_text(srt_text)

    return Response(vtt_text, mimetype="text/vtt")


@app.post("/api/srt/save")
def save_srt():
    try:
        payload = request.get_json(force=True)
        srt_path_raw = (payload.get("srt_path") or "").strip()

        media_dir, invalid_dir = _get_active_media_dir(payload.get("media_dir"))
        if invalid_dir:
            raise ValueError("Media directory not found")

        cues = payload.get("cues")

        if not srt_path_raw:
            raise ValueError("Missing srt_path")
        if not isinstance(cues, list) or not cues:
            raise ValueError("No cues to save")

        normalized: list[dict[str, str]] = []
        for cue in cues:
            if not isinstance(cue, dict):
                raise ValueError("Invalid cue payload")

            start = (cue.get("start") or "").strip()
            end = (cue.get("end") or "").strip()
            text = (cue.get("text") or "").strip()

            if not TIMECODE_RE.fullmatch(start) or not TIMECODE_RE.fullmatch(end):
                raise ValueError("Cue time must use HH:MM:SS,mmm format")

            normalized.append({"start": start, "end": end, "text": text})

        previous_end = 0.0
        for cue in normalized:
            start_s, end_s = _cue_to_seconds(cue)
            if end_s <= start_s:
                raise ValueError("Cue end time must be later than start time")
            if start_s < previous_end:
                raise ValueError("Cues cannot overlap or go backward")
            previous_end = end_s

        srt_path = _path_from_form_value(srt_path_raw, ALLOWED_SRT_EXTS, [media_dir, UPLOADS_DIR])
        srt_path.write_text(_serialize_srt(normalized), encoding="utf-8")

        return jsonify({"ok": True, "message": f"Saved {len(normalized)} cues."})

    except Exception as exc:
        return jsonify({"ok": False, "message": str(exc)}), 400


if __name__ == "__main__":
    _ensure_dirs()
    app.run(debug=True, port=5050)
