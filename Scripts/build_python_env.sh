#!/bin/bash
#
# build_python_env.sh
# Creates a Python virtual environment with the alignment dependencies
# at ~/Library/Application Support/SRT Workbench/python/
#
# The SRT Workbench app automatically finds it at this location.
#
set -euo pipefail

OUTPUT_DIR="$HOME/Library/Application Support/SRT Workbench/python"

echo "=== SRT Workbench — Python Environment Setup ==="
echo ""
echo "Output directory: $OUTPUT_DIR"

# Detect architecture
ARCH=$(uname -m)
echo "Architecture: $ARCH"

# --- Step 1: Find a suitable Python ---
echo ""
echo "--- Step 1: Finding Python 3.10+ ---"

PYTHON_BIN=""
for candidate in python3.10 python3.11 python3.12 python3; do
    if command -v "$candidate" &>/dev/null; then
        version=$("$candidate" --version 2>&1 | grep -oE '3\.[0-9]+')
        major_minor=$(echo "$version" | cut -d. -f2)
        if [[ "$major_minor" -ge 10 ]]; then
            PYTHON_BIN="$candidate"
            break
        fi
    fi
done

if [[ -z "$PYTHON_BIN" ]]; then
    echo "Error: Python 3.10+ not found."
    echo "Install with:  brew install python@3.10"
    exit 1
fi

echo "Using: $PYTHON_BIN ($($PYTHON_BIN --version))"

# --- Step 2: Create virtual environment ---
echo ""
echo "--- Step 2: Creating virtual environment ---"

if [[ -d "$OUTPUT_DIR" ]]; then
    echo "Removing existing environment..."
    rm -rf "$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"
"$PYTHON_BIN" -m venv "$OUTPUT_DIR"

# --- Step 3: Install dependencies ---
echo ""
echo "--- Step 3: Installing alignment dependencies ---"
echo "    (this may take a few minutes)"

"$OUTPUT_DIR/bin/pip" install --upgrade pip --quiet

"$OUTPUT_DIR/bin/pip" install \
    ctc-forced-aligner \
    Unidecode \
    python-docx \
    --no-cache-dir

# --- Step 4: Verify ---
echo ""
echo "--- Step 4: Verifying installation ---"
"$OUTPUT_DIR/bin/python3" -c "
from ctc_forced_aligner import AlignmentSingleton, generate_emissions
print('  ctc-forced-aligner: OK')
from unidecode import unidecode
print('  Unidecode: OK')
"

echo ""
echo "=== Python environment ready ==="
echo ""
echo "Location: $OUTPUT_DIR"
echo "Size:     $(du -sh "$OUTPUT_DIR" | cut -f1)"
echo ""
echo "The SRT Workbench app will automatically find this environment."
echo "You can now open the app and run alignment."
