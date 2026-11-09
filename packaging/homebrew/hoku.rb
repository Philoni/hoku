# Homebrew cask for a tap ("brew install --cask philoni/hoku/hoku").
# On each release: set version and sha256 (dist/Hoku-<version>.dmg.sha256).
cask "hoku" do
  version "0.9.0"
  sha256 "23527d82d89cb9b60833721568ad7664e4ec55f27714d13baefa09e7edf6707b"

  url "https://github.com/Philoni/hoku/releases/download/v#{version}/Hoku-#{version}.dmg",
      verified: "github.com/Philoni/hoku/"
  name "Hoku"
  desc "Menu bar app for Philips Hue lights"
  homepage "https://philoni.github.io/hoku/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "Hoku.app"

  zap trash: [
    "~/Library/Application Support/Hoku",
    "~/Library/Preferences/io.github.philoni.hoku.plist",
  ]

  caveats <<~EOS
    Hoku is signed with its own certificate, not notarized by Apple.
    On first launch: System Settings → Privacy & Security → Open Anyway.
  EOS
end
