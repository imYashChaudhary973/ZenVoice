#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
app_dir="$project_dir/build/ZenVoice.app"
contents_dir="$app_dir/Contents"

cd "$project_dir"
swift build -c release

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$project_dir/.build/release/ZenVoice" "$contents_dir/MacOS/ZenVoice"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"

codesign --force --sign - "$app_dir"
echo "$app_dir"
