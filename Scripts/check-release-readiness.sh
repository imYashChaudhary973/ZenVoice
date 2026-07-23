#!/bin/zsh
set -u

project_dir=${0:A:h:h}
app_path=${1:-"$project_dir/build/ZenVoice.app"}
blocker_count=0

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
    rg --count '^- \[ \]' "$project_dir/docs/RELEASE_READINESS.md" 2>/dev/null ||
        true
)
if [[ "${unfinished_items:-0}" -eq 0 ]]; then
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

if (( blocker_count > 0 )); then
    echo
    echo "Release blocked: $blocker_count gate(s) remain." >&2
    exit 2
fi

echo
echo "Automated release gate passed. Preserve the signed artifact and evidence."
