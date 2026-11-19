# Template for hlebtkachenko/homebrew-tap (Casks/retext.rb). Per release, set version and sha256
# from build/Retext-VERSION.dmg.sha256 or the release asset: see docs/RELEASING.md.
cask "retext" do
  version "1.3.0"
  sha256 "REPLACE_WITH_SHA256_OF_THE_RELEASE_DMG"

  url "https://github.com/hlebtkachenko/retext/releases/download/v#{version}/Retext-#{version}.dmg"
  name "Retext"
  desc "Fix, translate and rewrite selected text in any app with Claude Code"
  homepage "https://hlebtkachenko.github.io/retext/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "Retext.app"

  uninstall quit: "co.hleb.retext"

  zap trash: [
    "~/Library/Application Support/Retext",
    "~/Library/Preferences/co.hleb.retext.plist",
  ]
end
