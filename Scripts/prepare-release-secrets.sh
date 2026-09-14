#!/bin/zsh
set -euo pipefail

# Prints the gh secret set commands needed to upload BuilderVoice release secrets.
# It validates that local file paths exist and that required text variables are set,
# but it NEVER prints or exports the secret values themselves.
#
# Usage:
#   export BUILDERVOICE_SIGNING_IDENTITY="Developer ID Application: ..."
#   export BUILDERVOICE_SIGNING_CERTIFICATE_PASSWORD="..."
#   export BUILDERVOICE_NOTARY_KEY_ID="..."
#   export BUILDERVOICE_NOTARY_ISSUER_ID="..."
#   export BUILDERVOICE_SIGNING_CERTIFICATE_PATH="/path/to/cert.p12.base64"
#   export BUILDERVOICE_NOTARY_KEY_PATH="/path/to/key.p8.base64"
#   ./Scripts/prepare-release-secrets.sh

required_text=(
  BUILDERVOICE_SIGNING_IDENTITY
  BUILDERVOICE_SIGNING_CERTIFICATE_PASSWORD
  BUILDERVOICE_NOTARY_KEY_ID
  BUILDERVOICE_NOTARY_ISSUER_ID
)

required_files=(
  BUILDERVOICE_SIGNING_CERTIFICATE_PATH
  BUILDERVOICE_NOTARY_KEY_PATH
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
  print >&2 "  export BUILDERVOICE_SIGNING_IDENTITY='Developer ID Application: ...'"
  print >&2 "  export BUILDERVOICE_SIGNING_CERTIFICATE_PASSWORD='...'"
  print >&2 "  export BUILDERVOICE_NOTARY_KEY_ID='...'"
  print >&2 "  export BUILDERVOICE_NOTARY_ISSUER_ID='...'"
  print >&2 "  export BUILDERVOICE_SIGNING_CERTIFICATE_PATH='/path/to/cert.p12.base64'"
  print >&2 "  export BUILDERVOICE_NOTARY_KEY_PATH='/path/to/key.p8.base64'"
  exit 1
fi

print "Run these commands from the repo root to upload the secrets:"
print ""
printf 'gh secret set BUILDERVOICE_SIGNING_CERTIFICATE < "$BUILDERVOICE_SIGNING_CERTIFICATE_PATH"\n'
printf 'gh secret set BUILDERVOICE_NOTARY_KEY < "$BUILDERVOICE_NOTARY_KEY_PATH"\n'
printf 'gh secret set BUILDERVOICE_SIGNING_IDENTITY --body "$BUILDERVOICE_SIGNING_IDENTITY"\n'
printf 'gh secret set BUILDERVOICE_SIGNING_CERTIFICATE_PASSWORD --body "$BUILDERVOICE_SIGNING_CERTIFICATE_PASSWORD"\n'
printf 'gh secret set BUILDERVOICE_NOTARY_KEY_ID --body "$BUILDERVOICE_NOTARY_KEY_ID"\n'
printf 'gh secret set BUILDERVOICE_NOTARY_ISSUER_ID --body "$BUILDERVOICE_NOTARY_ISSUER_ID"\n'
print ""
print "These commands reference the environment variables you exported. They do not print the values."
