#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
app_dir="$project_dir/build/ZenVoice.app"
contents_dir="$app_dir/Contents"
frameworks_dir="$contents_dir/Frameworks"
brand_dir="$project_dir/Resources/Brand"
icon_path="$project_dir/build/ZenVoice.icns"
entitlements_path="$project_dir/Resources/ZenVoice.entitlements"
signing_identity=${ZENVOICE_SIGNING_IDENTITY:-}

cd "$project_dir"
swift build -c release
"$project_dir/Scripts/generate-app-icon.sh" \
    "$brand_dir/ZenLogo.png" \
    "$icon_path"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$frameworks_dir"
cp "$project_dir/.build/release/ZenVoice" "$contents_dir/MacOS/ZenVoice"
cp -R "$project_dir/.build/release/whisper.framework" "$frameworks_dir/"
cp -R "$project_dir/.build/release/llama.framework" "$frameworks_dir/"
install_name_tool \
    -add_rpath "@executable_path/../Frameworks" \
    "$contents_dir/MacOS/ZenVoice"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$brand_dir/ZenLogo.png" "$contents_dir/Resources/ZenLogo.png"
cp "$icon_path" "$contents_dir/Resources/ZenVoice.icns"

if [[ -z "$signing_identity" ]]; then
    signing_identity=$(
        security find-identity -v -p codesigning |
            awk '/"Apple Development:/ { print $2; exit }'
    )
fi

if [[ -n "$signing_identity" ]]; then
    codesign \
        --force \
        --options runtime \
        --timestamp=none \
        --sign "$signing_identity" \
        "$frameworks_dir/whisper.framework"
    codesign \
        --force \
        --options runtime \
        --timestamp=none \
        --sign "$signing_identity" \
        "$frameworks_dir/llama.framework"
    codesign \
        --force \
        --options runtime \
        --timestamp=none \
        --entitlements "$entitlements_path" \
        --sign "$signing_identity" \
        "$app_dir"
    echo "Signed with Apple Development identity: $signing_identity"
else
    codesign \
        --force \
        --options runtime \
        --sign - \
        "$frameworks_dir/whisper.framework"
    codesign \
        --force \
        --options runtime \
        --sign - \
        "$frameworks_dir/llama.framework"
    codesign \
        --force \
        --options runtime \
        --entitlements "$entitlements_path" \
        --sign - \
        "$app_dir"
    echo "Warning: no Apple Development identity found; used ad-hoc signing." >&2
    echo "macOS permissions may need approval after every rebuild." >&2
fi

echo "$app_dir"
