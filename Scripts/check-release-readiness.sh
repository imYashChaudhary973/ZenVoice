#!/bin/zsh
set -u

project_dir=${0:A:h:h}
app_path=${1:-"$project_dir/build/ZenVoice.app"}
distribution_archive=${2:-"$project_dir/build/ZenVoice-distribution.zip"}
blocker_count=0
source_cdhash=""

pass() {
    echo "PASS  $1"
}

block() {
    echo "BLOCK $1" >&2
    blocker_count=$((blocker_count + 1))
}

require_file() {
    if [[ -f "$project_dir/$1" ]]; then
        pass "$1 exists"
    else
        block "$1 is missing"
    fi
}

require_file "THIRD_PARTY_NOTICES.md"
require_file "docs/PRIVACY.md"
require_file "docs/SECURITY_REVIEW.md"
require_file "docs/RELEASE_READINESS.md"

if [[ -f "$project_dir/LICENSE" ]]; then
    pass "ZenVoice project licence exists"
else
    block "ZenVoice project licence has not been selected"
fi

unfinished_items=$(
    grep -cE '^- \[ \]' "$project_dir/docs/RELEASE_READINESS.md" 2>/dev/null
)
checklist_status=$?
if (( checklist_status > 1 )); then
    block "manual release checklist could not be inspected"
elif [[ "${unfinished_items:-0}" -eq 0 ]]; then
    pass "manual release checklist is complete"
else
    block "manual release checklist has $unfinished_items unfinished items"
fi

secret_files=$(
    git -C "$project_dir" grep -IlE \
        '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|ghp_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})' \
        -- . ':!Scripts/check-release-readiness.sh' 2>/dev/null ||
        true
)
if [[ -z "$secret_files" ]]; then
    pass "no common secret pattern found in tracked files"
else
    block "possible secret pattern found in tracked file(s): ${secret_files//$'\n'/, }"
fi

if [[ ! -d "$app_path" ]]; then
    block "packaged app is missing at $app_path"
else
    if codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
        pass "nested code signatures are structurally valid"
    else
        block "nested code signature verification failed"
    fi

    signature_details=$(codesign -dvv "$app_path" 2>&1 || true)
    source_cdhash=$(
        codesign -dvvv "$app_path" 2>&1 |
            grep -m 1 '^CDHash=' ||
            true
    )
    if [[ "$signature_details" == *"Authority=Developer ID Application:"* ]]; then
        pass "app uses a Developer ID Application identity"
    else
        block "app is not signed with a Developer ID Application identity"
    fi

    if xcrun stapler validate "$app_path" >/dev/null 2>&1; then
        pass "Apple notarization ticket is stapled"
    else
        block "Apple notarization ticket is not stapled or is invalid"
    fi
fi

if [[ ! -f "$distribution_archive" ]]; then
    block "distribution artifact is missing at $distribution_archive"
else
    archive_inventory_valid=true
    if ! command -v zipinfo >/dev/null 2>&1; then
        block "zipinfo is required to inspect the distribution artifact"
        archive_inventory_valid=false
    elif ! archive_entries=$(zipinfo -1 "$distribution_archive" 2>/dev/null); then
        block "distribution artifact inventory could not be read"
        archive_inventory_valid=false
    elif [[ -z "$archive_entries" ]]; then
        block "distribution artifact is empty"
        archive_inventory_valid=false
    else
        unexpected_entries=$(
            printf '%s\n' "$archive_entries" |
                grep -Ev '^ZenVoice\.app(/.*)?$' ||
                true
        )
        unsafe_entries=$(
            printf '%s\n' "$archive_entries" |
                grep -E '(^/|(^|/)\.\.(/|$))' ||
                true
        )
        if [[ -n "$unexpected_entries" || -n "$unsafe_entries" ]]; then
            block "distribution artifact contains payload outside ZenVoice.app"
            archive_inventory_valid=false
        fi
    fi

    if [[ "$archive_inventory_valid" == true ]]; then
        artifact_temp=$(mktemp -d 2>/dev/null)
        if [[ -z "$artifact_temp" ]]; then
            block "temporary directory for distribution inspection could not be created"
        elif ! ditto -x -k "$distribution_archive" "$artifact_temp" >/dev/null 2>&1; then
            block "distribution artifact could not be extracted"
            rm -rf "$artifact_temp"
        else
            extracted_app="$artifact_temp/ZenVoice.app"
            artifact_valid=true
            if [[ ! -d "$extracted_app" || -L "$extracted_app" ]]; then
                block "distribution artifact does not contain a regular ZenVoice.app bundle"
                artifact_valid=false
            elif ! codesign --verify --deep --strict "$extracted_app" >/dev/null 2>&1; then
                block "distribution artifact has invalid nested code signatures"
                artifact_valid=false
            else
                extracted_signature=$(codesign -dvv "$extracted_app" 2>&1 || true)
                extracted_cdhash=$(
                    codesign -dvvv "$extracted_app" 2>&1 |
                        grep -m 1 '^CDHash=' ||
                        true
                )
                if [[ "$extracted_signature" != *"Authority=Developer ID Application:"* ]]; then
                    block "distribution artifact is not Developer-ID signed"
                    artifact_valid=false
                elif [[ -n "$source_cdhash" && "$extracted_cdhash" != "$source_cdhash" ]]; then
                    block "distribution artifact does not match the packaged app"
                    artifact_valid=false
                elif ! xcrun stapler validate "$extracted_app" >/dev/null 2>&1; then
                    block "distribution artifact has no valid stapled ticket"
                    artifact_valid=false
                elif ! spctl --assess --type execute "$extracted_app" >/dev/null 2>&1; then
                    block "distribution artifact is rejected by Gatekeeper"
                    artifact_valid=false
                fi
            fi

            if [[ "$artifact_valid" == true ]]; then
                if archive_sha256=$(shasum -a 256 "$distribution_archive"); then
                    archive_sha256=${archive_sha256%% *}
                    pass "distribution artifact contains only the packaged app and is signed, stapled, and Gatekeeper-approved"
                    pass "distribution SHA-256 is $archive_sha256"
                else
                    block "distribution artifact SHA-256 could not be calculated"
                fi
            fi
            rm -rf "$artifact_temp"
        fi
    fi
fi

if (( blocker_count > 0 )); then
    echo
    echo "Release blocked: $blocker_count gate(s) remain." >&2
    exit 2
fi

echo
echo "Automated release gate passed. Preserve the signed artifact and evidence."
