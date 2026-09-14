cask "builderhelm-voice" do
  version "0.4.4"
  sha256 "8c7dbf30beccfe505ba0ab8ebca58d06f00bfb91d5e57de9207cc4a7535ed6b2"

  url "https://github.com/imYashChaudhary973/BuilderHelm-Voice/releases/download/v0.4.4/BuilderVoice.dmg"
  name "BuilderHelm Voice"
  desc "Privacy-first macOS speech capture, transcription, and lecture summaries"
  homepage "https://github.com/imYashChaudhary973/BuilderHelm-Voice"

  auto_updates true

  app "BuilderVoice.app"

  zap trash: [
    "~/Library/Application Support/com.builderhelm.voice",
    "~/Library/Caches/com.builderhelm.voice",
    "~/Library/Preferences/com.builderhelm.voice.plist",
  ]
end
