#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: generate-app-icon.sh SOURCE_PNG OUTPUT_ICNS" >&2
    exit 64
fi

source_png=$1
output_icns=$2
temporary_dir=$(mktemp -d)
iconset_dir="$temporary_dir/ZenVoice.iconset"

cleanup() {
    rm -rf "$temporary_dir"
}
trap cleanup EXIT

mkdir -p "$iconset_dir"

sips -z 16 16 "$source_png" --out "$iconset_dir/icon_16x16.png" >/dev/null
sips -z 32 32 "$source_png" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$source_png" --out "$iconset_dir/icon_32x32.png" >/dev/null
sips -z 64 64 "$source_png" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$source_png" --out "$iconset_dir/icon_128x128.png" >/dev/null
sips -z 256 256 "$source_png" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$source_png" --out "$iconset_dir/icon_256x256.png" >/dev/null
sips -z 512 512 "$source_png" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$source_png" --out "$iconset_dir/icon_512x512.png" >/dev/null
cp "$source_png" "$iconset_dir/icon_512x512@2x.png"

mkdir -p "${output_icns:h}"
iconutil -c icns "$iconset_dir" -o "$output_icns"
