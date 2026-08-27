#!/bin/zsh
set -euo pipefail

# Prints the gh secret set commands needed to upload ZenVoice release secrets.
# It validates that local file paths exist and that required text variables are set,
# but it NEVER prints or exports the secret values themselves.
#
# Usage:
#   export ZENVOICE_SIGNING_IDENTITY="Developer ID Application: ..."
#   export ZENVOICE_SIGNING_CERTIFICATE_PASSWORD="..."
#   export ZENVOICE_NOTARY_KEY_ID="..."
#   export ZENVOICE_NOTARY_ISSUER_ID="..."
#   export ZENVOICE_SIGNING_CERTIFICATE_PATH="/path/to/cert.p12.base64"
#   export ZENVOICE_NOTARY_KEY_PATH="/path/to/key.p8.base64"
#   ./Scripts/prepare-release-secrets.sh

required_text=(
  ZENVOICE_SIGNING_IDENTITY
  ZENVOICE_SIGNING_CERTIFICATE_PASSWORD
  ZENVOICE_NOTARY_KEY_ID
  ZENVOICE_NOTARY_ISSUER_ID
)

required_files=(
  ZENVOICE_SIGNING_CERTIFICATE_PATH
  ZENVOICE_NOTARY_KEY_PATH
)

missing=0

for var in "${required_text[@]}"; do
  if [[ -z "${(P)var:-}" ]]; then
    print >&2 "Missing environment variable: $var"
    missing=1
  fi
done

for var in "${required_files[@]}"; do
  path="${(P)var:-}"
  if [[ -z "$path" ]]; then
    print >&2 "Missing environment variable: $var"
    missing=1
  elif [[ ! -f "$path" ]]; then
    print >&2 "File does not exist ($var): $path"
    missing=1
  fi
done

if (( missing )); then
  print >&2 ""
  print >&2 "Set these variables and rerun:"
  print >&2 "  export ZENVOICE_SIGNING_IDENTITY='Developer ID Application: ...'"
  print >&2 "  export ZENVOICE_SIGNING_CERTIFICATE_PASSWORD='...'"
  print >&2 "  export ZENVOICE_NOTARY_KEY_ID='...'"
  print >&2 "  export ZENVOICE_NOTARY_ISSUER_ID='...'"
  print >&2 "  export ZENVOICE_SIGNING_CERTIFICATE_PATH='/path/to/cert.p12.base64'"
  print >&2 "  export ZENVOICE_NOTARY_KEY_PATH='/path/to/key.p8.base64'"
  exit 1
fi

print "Run these commands from the repo root to upload the secrets:"
print ""
printf 'gh secret set ZENVOICE_SIGNING_CERTIFICATE < "$ZENVOICE_SIGNING_CERTIFICATE_PATH"\n'
printf 'gh secret set ZENVOICE_NOTARY_KEY < "$ZENVOICE_NOTARY_KEY_PATH"\n'
printf 'gh secret set ZENVOICE_SIGNING_IDENTITY --body "$ZENVOICE_SIGNING_IDENTITY"\n'
printf 'gh secret set ZENVOICE_SIGNING_CERTIFICATE_PASSWORD --body "$ZENVOICE_SIGNING_CERTIFICATE_PASSWORD"\n'
printf 'gh secret set ZENVOICE_NOTARY_KEY_ID --body "$ZENVOICE_NOTARY_KEY_ID"\n'
printf 'gh secret set ZENVOICE_NOTARY_ISSUER_ID --body "$ZENVOICE_NOTARY_ISSUER_ID"\n'
print ""
print "These commands reference the environment variables you exported. They do not print the values."
