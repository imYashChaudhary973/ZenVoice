cask "zenvoice" do
  version "0.4.4"
  sha256 "8c7dbf30beccfe505ba0ab8ebca58d06f00bfb91d5e57de9207cc4a7535ed6b2"

  url "https://github.com/imYashChaudhary973/ZenVoice/releases/download/v0.4.4/ZenVoice.dmg"
  name "ZenVoice"
  desc "Privacy-first macOS speech capture, transcription, and lecture summaries"
  homepage "https://github.com/imYashChaudhary973/ZenVoice"

  auto_updates true

  app "ZenVoice.app"

  zap trash: [
    "~/Library/Application Support/ZenVoice",
    "~/Library/Caches/ZenVoice",
    "~/Library/Preferences/com.zenvoice.app.plist",
  ]
end
