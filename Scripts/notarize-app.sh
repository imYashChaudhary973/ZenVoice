#!/bin/zsh
set -euo pipefail

# Submits a built ZenVoice.app for Apple notarization and staples the
# ticket — the second half of the Developer ID pipeline that
# Scripts/build-app.sh starts.
#
# One-off prerequisites:
#   1. A "Developer ID Application" certificate in the login keychain.
#   2. Notary credentials stored once with:
#        xcrun notarytool store-credentials zenvoice-notary \
#            --apple-id <apple-id> --team-id <team-id>
#      (An App Store Connect API key works too; see `man notarytool`.)
#
# Usage:
#   ZENVOICE_SIGNING_IDENTITY="Developer ID Application: ..." \
#       ./Scripts/build-app.sh
#   ./Scripts/notarize-app.sh [path/to/ZenVoice.app]

project_dir=${0:A:h:h}
app_path=${1:-"$project_dir/build/ZenVoice.app"}
profile=${ZENVOICE_NOTARY_PROFILE:-zenvoice-notary}
archive_path="$project_dir/build/ZenVoice-notarization.zip"

if [[ ! -d "$app_path" ]]; then
    echo "Error: no app at $app_path — run Scripts/build-app.sh first." >&2
    exit 1
fi

# Notarization only accepts Developer ID signatures. Catching an Apple
# Development or ad-hoc build here saves an upload and a rejection.
if ! codesign -dvv "$app_path" 2>&1 |
    grep -q "Authority=Developer ID Application:"; then
    echo "Error: $app_path is not signed with a Developer ID Application" >&2
    echo "identity. Re-run Scripts/build-app.sh with" >&2
    echo "ZENVOICE_SIGNING_IDENTITY naming one." >&2
    exit 1
fi

rm -f "$archive_path"
ditto -c -k --keepParent "$app_path" "$archive_path"

xcrun notarytool submit "$archive_path" \
    --keychain-profile "$profile" \
    --wait

xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

echo "Notarized and stapled: $app_path"
