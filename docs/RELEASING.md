# Releasing Retext

A release is a universal `Retext-VERSION.dmg`, signed with a Developer ID Application certificate (hardened runtime, secure timestamp), notarized by Apple and stapled, attached to a GitHub release. `scripts/release.sh` does the work; `.github/workflows/release.yml` runs it on a pushed `vX.Y.Z` tag.

Never commit a signing identity's name, a `.p12`, a password or a team's credentials. Identities are passed by SHA-1 hash in environment variables.

## One-time setup

### On your Mac

1. Check that the Developer ID Application certificate and its private key are in your login keychain.
   ```bash
   security find-identity -v -p codesigning
   ```
   Expected: a line with `Developer ID Application` and a 40-character SHA-1 hash in front of it. That hash is your `RETEXT_RELEASE_IDENTITY`.

2. Create an app-specific password for notarization: [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords → add one named `retext-notary`. Copy it.

3. Store the notarization credentials as a keychain profile. Replace the two placeholders; the command asks for the app-specific password.
   ```bash
   xcrun notarytool store-credentials retext-notary --apple-id "YOUR_APPLE_ID_EMAIL" --team-id "YOUR_TEAM_ID"
   ```
   Expected: `Credentials saved to Keychain.` The team ID is the 10 characters in parentheses at the end of the identity line from step 1.

4. Export both variables in the shell you release from (add them to `~/.zshrc` to keep them). Replace the placeholder with the hash from step 1.
   ```bash
   export RETEXT_RELEASE_IDENTITY=YOUR_DEVELOPER_ID_SHA1
   export RETEXT_NOTARY_PROFILE=retext-notary
   ```
   Expected: `echo $RETEXT_NOTARY_PROFILE` prints `retext-notary`.

### GitHub Actions secrets

The release workflow needs five repository secrets:

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | The Developer ID Application certificate and private key, exported as `.p12`, base64-encoded |
| `MACOS_CERT_PASSWORD` | The password you gave the `.p12` export |
| `APPLE_ID` | Your Apple Account email |
| `APPLE_TEAM_ID` | Your 10-character team ID |
| `APPLE_APP_PASSWORD` | The app-specific password from step 2 above |

1. Export the certificate: Keychain Access → login → My Certificates → right-click the `Developer ID Application` certificate (with its key) → Export → format Personal Information Exchange (.p12) → save as `~/Desktop/retext-developer-id.p12` with a strong password.

2. Set the secrets. `gh secret set` without a value asks for it, so nothing lands in your shell history.
   ```bash
   base64 -i ~/Desktop/retext-developer-id.p12 | gh secret set MACOS_CERT_P12_BASE64 --repo hlebtkachenko/retext
   gh secret set MACOS_CERT_PASSWORD --repo hlebtkachenko/retext
   gh secret set APPLE_ID --repo hlebtkachenko/retext
   gh secret set APPLE_TEAM_ID --repo hlebtkachenko/retext
   gh secret set APPLE_APP_PASSWORD --repo hlebtkachenko/retext
   ```
   Expected: `gh secret list --repo hlebtkachenko/retext` lists all five.

3. Move the `.p12` out of `~/Desktop` into wherever you keep key backups. It holds the private key.

### Homebrew tap

1. Create the public repository `hlebtkachenko/homebrew-tap` on GitHub and clone it.
   ```bash
   gh repo create hlebtkachenko/homebrew-tap --public --description "Homebrew casks"
   gh repo clone hlebtkachenko/homebrew-tap ~/Developer/GitHub/homebrew-tap
   mkdir -p ~/Developer/GitHub/homebrew-tap/Casks
   ```
   Expected: an empty clone with a `Casks` folder. Fill it on the first release (see [Update the Homebrew cask](#update-the-homebrew-cask)).

### GitHub Pages (landing page)

1. Repository Settings → Pages → Build and deployment → Source: Deploy from a branch → Branch: `main`, folder `/docs` → Save. Or:
   ```bash
   gh api -X POST repos/hlebtkachenko/retext/pages -f "source[branch]=main" -f "source[path]=/docs"
   ```
   Expected: after a minute, https://hlebtkachenko.github.io/retext/ shows the landing page (`docs/index.html`).

2. Repository Settings → General → Social preview → Edit → upload `docs/images/social-preview.png`. GitHub has no API for this.

## Per release

Use a new version: tags up to `v1.3.0` predate this script and their sources have no icon or release script, so the first DMG ships with the next version. Set it once per shell; every command below uses it.

```bash
VERSION=1.4.0
```

1. Set `CFBundleShortVersionString` to `$VERSION` and raise `CFBundleVersion` by one in `Info.plist`, add the `CHANGELOG.md` entry, and commit on `main`.
   ```bash
   /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
   /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist
   ```
   Expected: the second command prints the new version. `scripts/release.sh` refuses to run when the two differ.

2. Test the build locally without notarization.
   ```bash
   scripts/release.sh "$VERSION" --skip-notarize
   ```
   Expected: `Built build/Retext-VERSION.dmg`, a SHA-256 line, and `rejected` / `source=Unnotarized Developer ID` from `spctl`: that rejection is correct for an un-notarized build. Open the DMG and run the app once.

3. Release. Pick one of the two paths.

   With GitHub Actions (needs the secrets above):
   ```bash
   git tag "v$VERSION"
   git push origin "v$VERSION"
   gh run watch --repo hlebtkachenko/retext "$(gh run list --repo hlebtkachenko/retext --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')"
   ```
   Expected: the run ends green and the release `v$VERSION` has `Retext-$VERSION.dmg` and `Retext-$VERSION.dmg.sha256`. Edit the generated release notes on GitHub if needed.

   Locally (uploads the app and the DMG to Apple's notary service, then publishes):
   ```bash
   scripts/release.sh "$VERSION"
   gh release create "v$VERSION" "build/Retext-$VERSION.dmg" "build/Retext-$VERSION.dmg.sha256" --repo hlebtkachenko/retext --title "Retext $VERSION" --generate-notes
   ```
   Expected: `scripts/release.sh` prints `Accepted` twice, `The validate action worked!` twice and `accepted` / `source=Notarized Developer ID`. Creating the tag through `gh release create` also starts the workflow, which rebuilds and replaces the two assets; that is harmless once the secrets are set.

4. Check what users download.
   ```bash
   curl -fL -o "/tmp/Retext-$VERSION.dmg" "https://github.com/hlebtkachenko/retext/releases/download/v$VERSION/Retext-$VERSION.dmg"
   spctl -a -vvv -t install "/tmp/Retext-$VERSION.dmg"
   xcrun stapler validate "/tmp/Retext-$VERSION.dmg"
   ```
   Expected: `accepted`, `source=Notarized Developer ID`, and `The validate action worked!`.

## Update the Homebrew cask

`Casks/retext.rb` in this repository is the template; the tap holds the live copy.

1. Put the release's version and SHA-256 into the template and copy it to the tap.
   ```bash
   SHA=$(curl -fsL "https://github.com/hlebtkachenko/retext/releases/download/v$VERSION/Retext-$VERSION.dmg.sha256" | cut -d' ' -f1)
   echo "$SHA"
   sed -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/retext.rb > ~/Developer/GitHub/homebrew-tap/Casks/retext.rb
   ```
   Expected: a 64-character hex hash, and the tap's `Casks/retext.rb` shows the new version and hash.

2. Publish, then audit and install from the tap.
   ```bash
   git -C ~/Developer/GitHub/homebrew-tap add Casks/retext.rb
   git -C ~/Developer/GitHub/homebrew-tap commit -m "feat: retext $VERSION"
   git -C ~/Developer/GitHub/homebrew-tap push
   brew tap hlebtkachenko/tap && brew update
   brew audit --cask --strict --online hlebtkachenko/tap/retext
   brew install --cask hlebtkachenko/tap/retext
   ```
   Expected: the push succeeds, the audit prints nothing (fix the template and repeat on findings), and the install puts `Retext.app` in `/Applications`. Anyone can then run `brew install --cask hlebtkachenko/tap/retext`.

## App icon

`Resources/AppIcon.icns`, `docs/images/icon-240.png` (Product Hunt thumbnail) and `docs/images/social-preview.png` (1280x640, GitHub and Open Graph) are a programmatic draft: a blue to violet rounded square with the SF Symbol `character.cursor.ibeam`, rendered by `scripts/make-icon.swift`. Replace them with a designed icon when one exists; keep the file names, and `build.sh` and `scripts/release.sh` pick it up. To re-render the draft:

```bash
swift scripts/make-icon.swift
```

Expected: `Wrote .../Resources/AppIcon.icns and docs/images/icon-240.png, social-preview.png`.

## What the release script does

1. Checks that `VERSION` equals `CFBundleShortVersionString`, that `RETEXT_RELEASE_IDENTITY` is set, and, unless `--skip-notarize`, that `RETEXT_NOTARY_PROFILE` is set. It stops before building otherwise.
2. Builds a universal (arm64 and x86_64) release binary and lays out `Retext.app` like `build.sh`, in a fresh temporary folder.
3. Signs the app with `--options runtime --timestamp`, notarizes a zip of it and staples the ticket to the app.
4. Builds the DMG (volume `Retext`, the app plus an `Applications` link), signs it, notarizes it and staples it.
5. Verifies with `stapler validate` and `spctl -a -vvv -t install`, then writes `build/Retext-VERSION.dmg` and `build/Retext-VERSION.dmg.sha256`.

`RETEXT_NOTARY_KEYCHAIN` (optional) names the keychain that holds the notary profile; the workflow sets it to its temporary keychain.
