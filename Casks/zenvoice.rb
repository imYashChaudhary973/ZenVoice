cask "zenvoice" do
  version "0.0.0-placeholder"
  sha256 :no_check

  url "https://github.com/zenvoice/ZenVoice/releases/download/v#{version}/ZenVoice-distribution.zip"
  name "ZenVoice"
  desc "Free, open-source, privacy-first macOS dictation"
  homepage "https://github.com/zenvoice/ZenVoice"

  auto_updates true

  app "ZenVoice.app"

  zap trash: [
    "~/Library/Application Support/ZenVoice",
    "~/Library/Caches/ZenVoice",
    "~/Library/Preferences/app.zenvoice.ZenVoice.plist",
  ]
end
