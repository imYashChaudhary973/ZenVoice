#!/bin/zsh
set -euo pipefail

# Bumps the ZenVoice marketing version in the places a release needs it.
# Usage:
#   ./Scripts/bump-version.sh 0.3.0

project_dir=${0:A:h:h}
new_version=${1:-}

if [[ -z "$new_version" ]]; then
    echo "Usage: ${0:t} <version>" >&2
    echo "Example: ${0:t} 0.3.0" >&2
    exit 1
fi

if [[ "$new_version" != [0-9]*.[0-9]*.[0-9]* ]]; then
    echo "Error: version must be in the form X.Y.Z" >&2
    exit 1
fi

cd "$project_dir"

# Resources/Info.plist CFBundleShortVersionString
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $new_version" \
    "$project_dir/Resources/Info.plist"

# CHANGELOG.md - add a new release section if the Unreleased block is empty.
changelog="$project_dir/CHANGELOG.md"
if grep -q "^## \[Unreleased\]$" "$changelog" 2>/dev/null; then
    # If Unreleased is empty (next line is another ##), insert a release block.
    if sed -n '/^## \[Unreleased\]$/,/^## \[/p' "$changelog" | tail -1 | grep -q '^## \['; then
        # Insert the new version section right after the Unreleased header.
        sed -i '' "/^## \[Unreleased\]$/a\\
\\
## [$new_version] - $(date +%Y-%m-%d)\\
" "$changelog"
    fi
fi

echo "Version bumped to $new_version"
echo "Review the diff, then commit and open a PR."
