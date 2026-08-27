#!/bin/zsh
# Reset ZenVoice local state to simulate a clean install on this Mac.
# This does NOT remove the app from /Applications; it deletes preferences,
# app support, keychain items, and permission approvals so the next launch
# behaves like a first launch.
#
# WARNING: This destroys local transcripts, settings, voice profile, and
# downloaded models. Use only for QA on non-production data.

set -euo pipefail

BUNDLE_ID="com.zenvoice.app"
APP_SUPPORT="${HOME}/Library/Application Support/ZenVoice"
GROUP_CONTAINER="${HOME}/Library/Group Containers/${BUNDLE_ID}"

# Quit ZenVoice if running
if pgrep -xq "ZenVoice"; then
  echo "Quitting ZenVoice…"
  osascript -e 'quit app "ZenVoice"' || true
  sleep 2
fi

# Remove NSUserDefaults
echo "Removing user defaults for ${BUNDLE_ID}…"
defaults delete "${BUNDLE_ID}" 2>/dev/null || true

# Remove app support
echo "Removing ${APP_SUPPORT}…"
rm -rf "${APP_SUPPORT}"

# Remove group container (if any)
echo "Removing ${GROUP_CONTAINER}…"
rm -rf "${GROUP_CONTAINER}"

# Remove cache
echo "Removing caches…"
rm -rf "${HOME}/Library/Caches/${BUNDLE_ID}"

# Remove preferences plist
echo "Removing preferences plist…"
rm -f "${HOME}/Library/Preferences/${BUNDLE_ID}.plist"

# Remove Sparkle-related state (update feed cache)
rm -f "${HOME}/Library/Preferences/${BUNDLE_ID}.sparkle.plist" 2>/dev/null || true

# Reset Accessibility and Microphone approvals for this bundle ID.
# This requires macOS to re-prompt on next launch.
echo "Resetting Accessibility and Microphone approvals…"
tccutil reset Accessibility "${BUNDLE_ID}" 2>/dev/null || true
tccutil reset Microphone "${BUNDLE_ID}" 2>/dev/null || true

# Remove keychain items for ZenVoice (transcript encryption key)
echo "Removing ZenVoice keychain items…"
security delete-generic-password -s "${BUNDLE_ID}" 2>/dev/null || true
security delete-generic-password -s "com.zenvoice.app.transcription" 2>/dev/null || true

# Remove old ZenVoice entry from Accessibility list if it still appears
echo "Done. On next launch, ZenVoice will prompt for onboarding, permissions, and model download."
