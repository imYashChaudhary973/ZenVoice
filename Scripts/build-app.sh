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

# SwiftUI's @State/@Binding/@Environment are macros, and the compiler plugin
# that expands them (libSwiftUIMacros.dylib) ships with Xcode — the Command
# Line Tools alone do not carry it. Building against a developer directory
# without the plugin does not fail with a clear message: every property wrapper
# silently fails to expand, surfacing instead as dozens of misleading
# "cannot find '$foo' in scope" and "'self' is immutable" errors in SwiftUI
# code that is perfectly valid. Resolve a toolchain that has it up front.
swiftui_macro_plugin="Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"
developer_dir=""
for candidate in \
    "${DEVELOPER_DIR:-}" \
    "$(xcode-select -p 2>/dev/null || true)" \
    /Applications/Xcode.app/Contents/Developer \
    /Applications/Xcode-beta.app/Contents/Developer
do
    [[ -n "$candidate" && -f "$candidate/$swiftui_macro_plugin" ]] || continue
    developer_dir="$candidate"
    break
done

if [[ -z "$developer_dir" ]]; then
    echo "Error: no Xcode toolchain provides $swiftui_macro_plugin." >&2
    echo "SwiftUI's @State macros cannot expand without it, and the Command" >&2
    echo "Line Tools do not include it. Install Xcode, or set DEVELOPER_DIR to" >&2
    echo "a developer directory that has the plugin." >&2
    exit 1
fi

export DEVELOPER_DIR="$developer_dir"

if [[ -z "$signing_identity" ]]; then
    signing_identity=$(
        security find-identity -v -p codesigning |
            awk '/"Apple Development:/ { print $2; exit }'
    )
fi

developer_id_signing=false
if [[ -n "$signing_identity" ]] && {
    [[ "$signing_identity" == *"Developer ID Application"* ]] ||
        security find-identity -v -p codesigning 2>/dev/null |
            grep -F -- "$signing_identity" |
            grep -q "Developer ID Application"
}; then
    developer_id_signing=true
fi

release_source_commit=""

verify_release_source_unchanged() {
    [[ "$developer_id_signing" == true ]] || return 0
    current_source_commit=$(git rev-parse HEAD)
    if [[ "$current_source_commit" != "$release_source_commit" ]] ||
        [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
        echo "Error: the source tree changed during the Developer ID build." >&2
        echo "Discard the candidate and rebuild from a clean worktree." >&2
        exit 1
    fi
}

verify_release_dependencies() {
    [[ "$developer_id_signing" == true ]] || return 0
    local dependency_json dependency_path dependency_revision
    local -a dependency_paths

    if ! dependency_json=$(swift package show-dependencies --format json); then
        echo "Error: SwiftPM dependency provenance could not be inspected." >&2
        exit 1
    fi
    dependency_paths=(
        "${(@f)$(printf '%s\n' "$dependency_json" |
            grep '"path"' |
            cut -d '"' -f 4)}"
    )
    for dependency_path in "${dependency_paths[@]}"; do
        [[ "$dependency_path" == "$project_dir" ]] && continue
        if [[ "$dependency_path" != "$project_dir/.build/checkouts/"* ]] ||
            [[ ! -d "$dependency_path/.git" ]]; then
            echo "Error: release build uses an editable or local dependency:" >&2
            echo "$dependency_path" >&2
            exit 1
        fi
        if [[ -n "$(git -C "$dependency_path" status --porcelain --untracked-files=all)" ]]; then
            echo "Error: release dependency checkout is dirty: $dependency_path" >&2
            exit 1
        fi
        dependency_revision=$(git -C "$dependency_path" rev-parse HEAD)
        if ! grep -Fq "\"revision\" : \"$dependency_revision\"" Package.resolved; then
            echo "Error: dependency revision is absent from Package.resolved:" >&2
            echo "$dependency_path @ $dependency_revision" >&2
            exit 1
        fi
    done
}

if [[ "$developer_id_signing" == true ]]; then
    if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
        echo "Error: Developer ID release builds require a clean worktree." >&2
        echo "Commit or remove every tracked and untracked change first." >&2
        exit 1
    fi
    release_source_commit=$(git rev-parse HEAD)

    # Clear ignored SwiftPM state so `swift package edit` overrides and modified
    # cached artifacts cannot enter a signed release under the pinned commit's
    # identity. Resolving again reconstructs dependencies from Package.swift
    # and Package.resolved before their paths, revisions, and status are checked.
    swift package reset
    swift package resolve
    verify_release_source_unchanged
    verify_release_dependencies
fi

swift build -c release
verify_release_source_unchanged
verify_release_dependencies

"$project_dir/Scripts/generate-app-icon.sh" \
    "$brand_dir/ZenLogo.png" \
    "$icon_path"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$frameworks_dir"
cp "$project_dir/.build/release/ZenVoice" "$contents_dir/MacOS/ZenVoice"
cp -R "$project_dir/.build/release/whisper.framework" "$frameworks_dir/"
install_name_tool \
    -add_rpath "@executable_path/../Frameworks" \
    "$contents_dir/MacOS/ZenVoice"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$brand_dir/ZenLogo.png" "$contents_dir/Resources/ZenLogo.png"
cp "$icon_path" "$contents_dir/Resources/ZenVoice.icns"
cp \
    "$project_dir/THIRD_PARTY_NOTICES.md" \
    "$contents_dir/Resources/THIRD_PARTY_NOTICES.md"

verify_release_source_unchanged
verify_release_dependencies

if [[ -n "$signing_identity" ]]; then
    # Developer ID distribution requires Apple's secure timestamp;
    # everyday Apple Development builds skip that network round-trip.
    timestamp_flag="--timestamp=none"
    if [[ "$developer_id_signing" == true ]]; then
        timestamp_flag="--timestamp"
    fi
    codesign \
        --force \
        --options runtime \
        "$timestamp_flag" \
        --sign "$signing_identity" \
        "$frameworks_dir/whisper.framework"
    codesign \
        --force \
        --options runtime \
        "$timestamp_flag" \
        --entitlements "$entitlements_path" \
        --sign "$signing_identity" \
        "$app_dir"
    if [[ "$timestamp_flag" == "--timestamp" ]]; then
        echo "Signed for distribution with: $signing_identity"
    else
        echo "Signed with Apple Development identity: $signing_identity"
    fi
else
    codesign \
        --force \
        --options runtime \
        --sign - \
        "$frameworks_dir/whisper.framework"
    codesign \
        --force \
        --options runtime \
        --entitlements "$entitlements_path" \
        --sign - \
        "$app_dir"
    echo "Warning: no Apple Development identity found; used ad-hoc signing." >&2
    echo "macOS permissions may need approval after every rebuild." >&2
fi

verify_release_source_unchanged
verify_release_dependencies

if [[ -n "$release_source_commit" ]]; then
    echo "Release source commit: $release_source_commit"
fi
echo "$app_dir"
