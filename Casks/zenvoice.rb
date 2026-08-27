cask "zenvoice" do
  version "0.4.2"
  sha256 "312b4349746aa7339dc4e9902b8dbed16c6658b684a061471a37b33478c86462"

  url "https://github.com/imYashChaudhary973/ZenVoice/releases/download/v0.4.2/ZenVoice.dmg"
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
