# Template for the owner's Homebrew tap (<owner>/homebrew-tap, Casks/retext.rb), not a published cask: the signed release is planned.
# Per release, the sed in docs/RELEASING.md sets version and sha256 from the release asset, the repository and homepage from REPO, and the bundle id from BUNDLE_ID.
cask "retext" do
  version "REPLACE_WITH_VERSION"
  sha256 "REPLACE_WITH_SHA256_OF_THE_RELEASE_DMG"

  url "https://github.com/hlebtkachenko/retext/releases/download/v#{version}/Retext-#{version}.dmg"
  name "Retext"
  desc "Fix, translate and rewrite selected text in any app with your own AI provider"
  homepage "https://hlebtkachenko.github.io/retext/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "Retext.app"

  uninstall quit: "dev.hapd.retext"

  zap trash: [
    "~/Library/Application Support/Retext",
    "~/Library/Preferences/dev.hapd.retext.plist",
    "~/Library/Preferences/co.hleb.retext.plist",
  ]
end
