# SRT Workbench

A native macOS app that generates accurately timed SRT subtitle files from video and a ground-truth script (.docx). Uses CTC forced alignment with a wav2vec2 ONNX model to produce word-level timestamps (~50ms accuracy), then groups words into subtitle-sized cues.

Unlike speech-to-text transcription, this approach uses your original script as the source of truth, so technical terms, proper nouns, and domain-specific language are always correct.

## Features

- **Generate tab** — Pick a video and .docx script, run alignment, get a timed SRT file
- **Review tab** — Play video with caption overlay, edit cue timecodes and text, save changes
- **2x playback speed** — Toggle with toolbar button or keyboard shortcut
- **Checklist progress** — Visual step-by-step progress during alignment
- **Auto-setup** — First launch creates a Python environment and downloads the alignment model automatically

## Requirements

- **macOS 14 (Sonoma)** or later
- **Python 3.10+** — Install via [Homebrew](https://brew.sh): `brew install python@3.12`
- **XcodeGen** — To generate the Xcode project: `brew install xcodegen`
- **Xcode 15+** — To build the app
- ~1.5 GB disk space for the alignment model (downloaded on first launch)

## Build from Source

```bash
# Clone the repo
git clone https://github.com/mouseykins/srt-workbench.git
cd srt-workbench

# Generate the Xcode project
xcodegen generate

# Open in Xcode and build (Cmd+B), or build from command line:
xcodebuild -project SRTWorkbench.xcodeproj -scheme SRTWorkbench -configuration Release
```

To create a distributable DMG:

```bash
Scripts/create_dmg.sh
```

## First Launch

On first launch, SRT Workbench automatically:

1. Creates a Python virtual environment at `~/Library/Application Support/SRT Workbench/python/`
2. Installs alignment dependencies (ctc-forced-aligner, python-docx, Unidecode)
3. Downloads the wav2vec2 ONNX model (~1.2 GB)

This only happens once. Subsequent launches skip straight to the app.

## Usage

### Generate Tab

1. Choose a media directory (or pick files individually)
2. Select a video file (.mp4, .mov, .mkv, .webm, .m4v)
3. Select a script file (.docx) — stage directions in [square brackets] are automatically filtered out
4. Click **Run Alignment**
5. The generated SRT file is saved to an `srt/` subfolder in the media directory

### Review Tab

After generation, the Review tab loads automatically with the video and SRT side by side. You can also load any video + SRT file pair manually.

- The currently spoken subtitle is highlighted in the cue list
- Click **Jump** on any cue to seek the video to that timecode
- Edit timecodes or subtitle text directly, then **Save SRT** (Cmd+S)

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘ Return | Play / Pause |
| ⌘ ← | Skip back 5 seconds |
| ⌘ → | Skip forward 5 seconds |
| ⌘ D | Toggle 1x / 2x speed |
| ⌘ S | Save SRT file |

## Architecture

Swift/SwiftUI app with a Python subprocess for the ML alignment pipeline:

- **UI**: SwiftUI with MVVM pattern (macOS 14+)
- **Audio extraction**: AVFoundation (no ffmpeg dependency)
- **Document parsing**: python-docx via Python subprocess
- **Alignment engine**: Python subprocess running ctc-forced-aligner with wav2vec2 ONNX model
- **Video playback**: AVKit with caption overlay and time-synced cue highlighting

## Project Structure

```
├── SRTWorkbench/              # Swift app source
│   ├── Models/                # SRTCue, SRTDocument
│   ├── Services/              # Alignment, audio extraction, parsing, setup
│   ├── ViewModels/            # Generate and Review logic
│   ├── Views/                 # SwiftUI views
│   ├── Utilities/             # Timecode formatting
│   └── Resources/             # alignment_runner.py, app icon, assets
├── Scripts/
│   ├── build_python_env.sh    # Manual Python env setup
│   ├── create_dmg.sh          # DMG packaging
│   └── generate_icon.swift    # App icon generator
└── project.yml                # XcodeGen project definition
```

## License

MIT
