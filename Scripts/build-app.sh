#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
app_dir="$project_dir/build/ZenVoice.app"
contents_dir="$app_dir/Contents"
brand_dir="$project_dir/Resources/Brand"
icon_path="$project_dir/build/ZenVoice.icns"

cd "$project_dir"
swift build -c release
"$project_dir/Scripts/generate-app-icon.sh" \
    "$brand_dir/ZenLogo.png" \
    "$icon_path"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$project_dir/.build/release/ZenVoice" "$contents_dir/MacOS/ZenVoice"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$brand_dir/ZenLogo.png" "$contents_dir/Resources/ZenLogo.png"
cp "$icon_path" "$contents_dir/Resources/ZenVoice.icns"

codesign --force --sign - "$app_dir"
echo "$app_dir"
