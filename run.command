#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ -w "$SCRIPT_DIR" ]; then
  VENV_DIR="$SCRIPT_DIR/.venv"
else
  VENV_DIR="$HOME/.srt-generator/.venv"
fi

if [ ! -x "$VENV_DIR/bin/python" ]; then
  echo "Virtual environment not found at $VENV_DIR. Running setup first..."
  ./setup.command
fi

if [ ! -x "$VENV_DIR/bin/python" ]; then
  echo "Error: virtual environment is still missing at $VENV_DIR"
  exit 1
fi

LOCAL_FFMPEG="$SCRIPT_DIR/bin/ffmpeg"
if [ -x "$LOCAL_FFMPEG" ]; then
  export FFMPEG_BIN="$LOCAL_FFMPEG"
elif command -v ffmpeg >/dev/null 2>&1; then
  export FFMPEG_BIN="$(command -v ffmpeg)"
else
  echo "Error: ffmpeg is not available."
  echo "Add a binary at ./bin/ffmpeg or install Homebrew + ffmpeg."
  echo "Homebrew install (optional): /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  echo "Then: brew install ffmpeg"
  exit 1
fi

echo "Using virtual environment: $VENV_DIR"
echo "Starting SRT Workbench on http://127.0.0.1:5050 ..."
(open "http://127.0.0.1:5050" >/dev/null 2>&1 &) || true
"$VENV_DIR/bin/python" app.py
