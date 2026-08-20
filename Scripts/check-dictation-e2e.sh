#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
audio_file=${ZENVOICE_E2E_AUDIO_FILE:-"$project_dir/Datasets/common-voice-spontaneous-4.0/prepared-v1/audio/train/cv-sps-en-70876.wav"}
model_file=${ZENVOICE_MODEL_PATH:-"$HOME/Library/Application Support/ZenVoice/Models/ggml-medium.bin"}
app_dir="${TMPDIR:-/tmp}/ZenVoice-E2E-$$.app"
log_file="${TMPDIR:-/tmp}/ZenVoice-E2E-$$.log"
pid=""

cleanup() {
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
    rm -rf "$app_dir" "$log_file"
}
trap cleanup EXIT

[[ -f "$audio_file" ]] || {
    echo "FAIL  deterministic audio fixture is missing: $audio_file" >&2
    exit 1
}
[[ -f "$model_file" ]] || {
    echo "FAIL  verified model is missing: $model_file" >&2
    exit 1
}

ZENVOICE_BUILD_CONFIGURATION=debug \
ZENVOICE_APP_DIR="$app_dir" \
    "$project_dir/Scripts/build-app.sh" >/dev/null

ZENVOICE_E2E_AUDIO_FILE="$audio_file" \
ZENVOICE_E2E_AUTORUN=1 \
ZENVOICE_MODEL_PATH="$model_file" \
    "$app_dir/Contents/MacOS/ZenVoice" >"$log_file" 2>&1 &
pid=$!

for _ in {1..400}; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$pid" 2>/dev/null; then
    echo "FAIL  deterministic dictation did not terminate within 40 seconds" >&2
    exit 1
fi
wait "$pid" || true
cat "$log_file"

result=$(grep -E 'ZENVOICE_E2E_RESULT (success|failure)' "$log_file" | tail -n 1 || true)
[[ "$result" == ZENVOICE_E2E_RESULT\ success* ]] || {
    echo "FAIL  deterministic dictation failed: ${result:-no result}" >&2
    exit 1
}

elapsed=${result##* }
if ! awk -v elapsed="$elapsed" 'BEGIN { exit !(elapsed <= 1.5) }'; then
    echo "FAIL  deterministic stop-to-complete took ${elapsed}s (limit 1.5s)" >&2
    exit 1
fi

echo "PASS  deterministic stop-to-complete ${elapsed}s"
