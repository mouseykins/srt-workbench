#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ -w "$SCRIPT_DIR" ]; then
  VENV_DIR="$SCRIPT_DIR/.venv"
else
  VENV_DIR="$HOME/.srt-generator/.venv"
fi

echo "[1/4] Checking Python 3..."
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is not installed."
  echo "Install Xcode Command Line Tools or Python 3, then rerun setup.command."
  exit 1
fi

echo "[2/4] Creating/updating virtual environment..."
mkdir -p "$(dirname "$VENV_DIR")"
if python3 -m venv --copies "$VENV_DIR" 2>/tmp/srtgen_venv_err.log; then
  :
else
  echo "venv --copies failed; retrying with default venv mode..."
  rm -rf "$VENV_DIR"
  if ! python3 -m venv "$VENV_DIR"; then
    echo "Error: failed to create virtual environment."
    cat /tmp/srtgen_venv_err.log || true
    exit 1
  fi
fi

echo "Using virtual environment: $VENV_DIR"

echo "[3/4] Installing Python dependencies..."
"$VENV_DIR/bin/python" -m pip install --upgrade pip
"$VENV_DIR/bin/pip" install -r requirements.txt

TARGET_MEDIA_DIR="$SCRIPT_DIR/media"
mkdir -p "$TARGET_MEDIA_DIR"
echo "Created/verified media directory: $TARGET_MEDIA_DIR"

echo "[4/4] Checking ffmpeg..."
LOCAL_FFMPEG="$SCRIPT_DIR/bin/ffmpeg"
if [ -x "$LOCAL_FFMPEG" ]; then
  echo "ffmpeg found in project: $LOCAL_FFMPEG"
elif command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg found on PATH: $(command -v ffmpeg)"
else
  echo "Warning: ffmpeg was not found on PATH."
  echo "This app needs ffmpeg to extract audio from videos."
  echo "Option 1: Add a local binary at ./bin/ffmpeg"
  echo "Option 2: Install Homebrew, then: brew install ffmpeg"
fi

echo ""
echo "Setup complete. Next run: ./run.command"
