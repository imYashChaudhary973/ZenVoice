#!/bin/zsh
set -euo pipefail

# Submits a built ZenVoice.app for Apple notarization, staples the ticket, and
# packages the verified app for direct download — the second half of the
# Developer ID pipeline that Scripts/build-app.sh starts.
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
submission_archive_path="$project_dir/build/ZenVoice-notarization-upload.zip"
distribution_archive_path="$project_dir/build/ZenVoice-distribution.zip"

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

rm -f "$submission_archive_path" "$distribution_archive_path"
ditto -c -k --keepParent "$app_path" "$submission_archive_path"

xcrun notarytool submit "$submission_archive_path" \
    --keychain-profile "$profile" \
    --wait

xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

# The upload archive was created before stapling and is not the direct-download
# artifact. Package the verified, stapled app again so QA and distribution use
# the same immutable file.
ditto -c -k --keepParent "$app_path" "$distribution_archive_path"
distribution_sha256=$(shasum -a 256 "$distribution_archive_path")
distribution_sha256=${distribution_sha256%% *}

echo "Notarized and stapled app: $app_path"
echo "Distribution artifact: $distribution_archive_path"
echo "Distribution SHA-256: $distribution_sha256"
