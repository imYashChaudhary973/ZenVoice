#!/bin/zsh
# Deterministic E2E helper for ZenVoice QA.
# Builds a debug .app, generates a 16 kHz mono fixture, launches the app with
# ZENVOICE_E2E_AUDIO_FILE override, and prints the QA steps to perform.
#
# Usage: ./Scripts/run-qa-deterministic-e2e.sh /path/to/source.wav
# If no source is given, creates a short silence fixture.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
SOURCE_WAV="${1:-}"
FIXTURE="/tmp/zenvoice-qa-e2e.wav"
BUILD_APP="${REPO_ROOT}/build/ZenVoice.app"

echo "Building debug app…"
(cd "${REPO_ROOT}" && swift build && ./Scripts/build-app.sh)

if [[ -n "${SOURCE_WAV}" && -f "${SOURCE_WAV}" ]]; then
  echo "Normalizing ${SOURCE_WAV} → ${FIXTURE}"
  afconvert "${SOURCE_WAV}" "${FIXTURE}" -f WAVE -d LEI16@16000 -c 1
else
  echo "Creating 5-second silence fixture at ${FIXTURE}"
  sox -n -r 16000 -c 1 -b 16 "${FIXTURE}" trim 0 5 2>/dev/null || \
    afconvert /System/Library/Sounds/Ping.aiff "${FIXTURE}" -f WAVE -d LEI16@16000 -c 1 2>/dev/null || true
fi

if [[ ! -f "${FIXTURE}" ]]; then
  echo "Failed to create fixture. Install sox or provide a source WAV."
  exit 1
fi

echo ""
echo "Launching ZenVoice with deterministic audio override…"
echo "ZENVOICE_E2E_AUDIO_FILE=${FIXTURE}"
echo ""

# Quit any running ZenVoice first
osascript -e 'quit app "ZenVoice"' 2>/dev/null || true
sleep 1

ZENVOICE_E2E_AUDIO_FILE="${FIXTURE}" open "${BUILD_APP}"

echo "App launched. Perform these manual steps:"
echo "1. Complete onboarding if prompted."
echo "2. Open TextEdit and place the cursor in a document."
echo "3. Press the dictation shortcut and stop it."
echo "4. Confirm the fixture transcript is inserted and appears in History."
echo "5. Repeat for each language profile under test."
