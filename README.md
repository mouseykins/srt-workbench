# SRT Workbench

A local web app for generating accurately timed SRT caption files from a video and its written script. Built for technical education videos where standard transcription services mangle terminology — because you supply the ground-truth script, every technical term, spelling, and capitalisation comes out exactly right.

---

## How it works

Most transcription services do speech-to-text and get technical terms wrong. This tool flips that: you provide the correct text, and the app works out *when* each word is spoken.

It uses **CTC forced alignment** (a wav2vec2 speech recognition model running locally via ONNX) to match your script against the audio frame-by-frame, producing word-level timestamps accurate to ~50ms. Long lines are automatically split into subtitle-length chunks (≤4.5 seconds each).

**Pipeline:**
1. Extract audio from the video (ffmpeg)
2. Run CTC forced alignment against your script (ctc-forced-aligner)
3. Map word timestamps back to script lines, splitting where needed
4. Output a ready-to-use `.srt` file

---

## Requirements

| Dependency | Notes |
|---|---|
| **Python 3.10+** | 3.10 recommended; 3.13 has build issues with some dependencies |
| **ffmpeg** | For audio extraction |
| **~1.2 GB disk space** | For the alignment model (auto-downloaded on first run to `~/ctc_forced_aligner/`) |

Python packages (installed automatically by setup):
- `Flask` — web UI
- `ctc-forced-aligner` — forced alignment engine
- `python-docx` — reads `.docx` script files
- `Unidecode` — text normalisation for the aligner

---

## Setup (macOS)

### Option A — Double-click launcher (easiest)

```bash
# First time only
./setup.command    # creates .venv and installs dependencies

# Every time after
./run.command      # starts the app and opens http://127.0.0.1:5050
```

Both scripts are in the root of the repo. macOS may ask you to confirm running them the first time — right-click → Open if so.

### Option B — Terminal

```bash
# Install system dependencies (once)
brew install ffmpeg python@3.10

# Create virtual environment and install packages (once)
python3.10 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Run
python app.py
```

Then open **http://127.0.0.1:5050** in your browser.

---

## Using the app

### Generate page

1. Set your **Media Directory** — the folder where your videos and scripts live (the app will scan it for supported files)
2. Select a **video** and its matching **script** (.docx) — or upload them directly
3. Click **Run Alignment** — a spinner shows while processing (typically 1–3 minutes depending on video length)
4. When done, the app automatically takes you to the Review & Edit page

### Review & Edit page

- The video plays with captions overlaid
- The **Cue Editor** panel lists every subtitle entry with editable text and timestamps
- The active cue highlights automatically as the video plays
- Click **Jump** on any cue to seek the video to that point
- Edit any text or timing directly in the fields
- Click **Save SRT** to write changes back to the file

### Getting your SRT file

Generated files are saved to the `uploads/` folder inside the project directory. Copy the `.srt` file from there to wherever you need it.

---

## Script format (.docx)

- One paragraph per spoken section
- Lines in **[square brackets]** are treated as stage directions and skipped (e.g. `[Cut to diagram]`)
- Empty paragraphs are ignored
- Everything else is treated as spoken dialogue — use exactly the spelling, capitalisation, and terminology you want in the captions

---

## Project structure

```
srt-workbench/
├── app.py              # Flask app — routes, file handling, SRT save/serve
├── generate_srt.py     # Core pipeline: audio extraction + CTC alignment
├── requirements.txt    # Python dependencies
├── setup.command       # macOS one-click setup script
├── run.command         # macOS one-click launch script
├── templates/
│   ├── index.html      # Generate page
│   └── player.html     # Review & Edit page
└── static/
    ├── style.css       # UI styles
    └── player.js       # Cue editor, video sync, save logic
```

**Not in the repo** (created locally or downloaded automatically):
- `.venv/` — Python virtual environment (~500MB)
- `media/` — your media files (point the app at wherever these live)
- `uploads/` — temporary files and generated SRTs
- `~/ctc_forced_aligner/model.onnx` — alignment model (~1.2GB, auto-downloaded)

---

## Git workflow

### Pushing changes (from any machine)

```bash
git add -A
git commit -m "describe what changed"
git push
```

### Pulling updates (on another machine)

```bash
git pull
```

### Setting up on a new machine

```bash
brew install gh git
gh auth login
git clone https://github.com/mouseykins/srt-workbench.git
cd srt-workbench
./setup.command
./run.command
```

---

## Troubleshooting

**ffmpeg not found**
Install via Homebrew (`brew install ffmpeg`), or place an ffmpeg binary at `./bin/ffmpeg` inside the project folder and `run.command` will find it automatically.

**"Alignment model downloading" takes a long time**
The wav2vec2 ONNX model is ~1.2GB and only downloads once, to `~/ctc_forced_aligner/model.onnx`. Subsequent runs load it from disk and are much faster.

**Captions are slightly off-timing**
Use the Review & Edit page to nudge individual cue start/end times, then Save SRT. The alignment is typically within a few hundred milliseconds but videos with long silences or music-only sections can drift slightly.

**App won't start / venv errors**
Delete `.venv/` and rerun `./setup.command` to rebuild from scratch.
