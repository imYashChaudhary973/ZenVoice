cask "zenvoice" do
  version "0.4.1"
  sha256 "332c18253c2ac501febfe8076d2b6978c6c22a0e520d4c37c7bcf6f73b5d7639"

  url "https://github.com/imYashChaudhary973/ZenVoice/releases/download/v#{version}/ZenVoice.dmg"
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
