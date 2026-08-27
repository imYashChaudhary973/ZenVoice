cask "zenvoice" do
  version "0.4.3"
  sha256 "552ebb3a101edb97be704d4b4199f0d1bb1bddfb378add6cbfcf0c0f72c021dc"

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
