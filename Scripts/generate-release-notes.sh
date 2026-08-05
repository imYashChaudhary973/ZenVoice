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

# Print the section for this version if it exists, otherwise Unreleased.
awk -v ver="$version" '
    /^## \[Unreleased\]/ { start=1; next }
    start && /^## \[/ { exit }
    start { print }
' "$changelog"

echo ""
echo "## Artifacts"
echo "- ZenVoice-distribution.zip contains the signed and notarized ZenVoice.app."
echo "  Verify with: spctl --assess --type execute ZenVoice.app"
