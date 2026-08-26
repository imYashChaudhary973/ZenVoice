cask "zenvoice" do
  version "0.4.0"
  sha256 "33c5399927888386e7e755920a7d96af1e990c511c5e9b39c35681c048e30b94"

  url "https://github.com/imYashChaudhary973/ZenVoice/releases/download/v#{version}/ZenVoice.dmg"
  name "ZenVoice"
  desc "Privacy-first macOS speech capture, transcription, and lecture summaries"
  homepage "https://github.com/imYashChaudhary973/ZenVoice"

  auto_updates true

  app "ZenVoice.app"

  zap trash: [
    "~/Library/Application Support/ZenVoice",
    "~/Library/Caches/ZenVoice",
    "~/Library/Preferences/dev.yashchaudhary.ZenVoice.plist",
  ]
end
