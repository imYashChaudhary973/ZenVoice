#!/bin/zsh
set -euo pipefail

# Generates a GitHub release notes stub from CHANGELOG.md.
# Usage:
#   ./Scripts/generate-release-notes.sh 0.3.0

project_dir=${0:A:h:h}
version=${1:-}

if [[ -z "$version" ]]; then
    echo "Usage: ${0:t} <version>" >&2
    exit 1
fi

changelog="$project_dir/CHANGELOG.md"
if [[ ! -f "$changelog" ]]; then
    echo "CHANGELOG.md not found" >&2
    exit 1
fi

# Print the section for this version, failing loudly when CHANGELOG.md has
# no section for it: a silently empty stub would publish a bare release.
section=$(awk -v ver="$version" '
    index($0, "## [" ver "]") == 1 { start=1; next }
    start && /^## \[/ { exit }
    start { print }
    /^## \[/ { start=0 }
' "$changelog")

if [[ -z "$section" ]]; then
    echo "Error: CHANGELOG.md has no '## [$version]' section." >&2
    echo "Add release notes for $version before generating release notes." >&2
    exit 1
fi

print -r -- "$section"

echo ""
echo "## Artifacts"
echo "- ZenVoice.dmg contains the signed, notarized, and stapled ZenVoice.app."
echo "  Drag ZenVoice.app to Applications, then verify with:"
echo "  spctl --assess --type execute /Applications/ZenVoice.app"
