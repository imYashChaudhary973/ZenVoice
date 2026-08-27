cask "zenvoice" do
  version "0.4.3"
  sha256 "3e44253176d8cb3cefa1c8b2d2afe42387a0d9f85a2ac65994c790511d995fd6"

  url "https://github.com/imYashChaudhary973/ZenVoice/releases/download/v0.4.3/ZenVoice.dmg"
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
