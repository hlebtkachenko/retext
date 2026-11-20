# Releasing Retext

> [!NOTE]
> This is the procedure for the planned signed release and is not used yet. For now a release is a `vX.Y.Z` tag and a GitHub release with notes and no assets; users build from source. The signed DMG, the Homebrew cask and the GitHub Pages landing page come later.

A signed release is a universal `Retext-VERSION.dmg`, signed with a Developer ID Application certificate (hardened runtime, secure timestamp), notarized by Apple and stapled, attached to a GitHub release. `scripts/release.sh` does the work; `.github/workflows/release.yml` runs it when started by hand for an existing `vX.Y.Z` tag.

Run the commands from the root of this repository. They use `REPO` (owner/name of this repository, taken from the `origin` remote, so a fork works unchanged even with an `upstream` remote), `OWNER` and `BUNDLE_ID` (the `CFBundleIdentifier` in `Info.plist`); set them once per shell:

```bash
REPO=$(git remote get-url origin | sed -E 's#(\.git)?$##; s#^.*github\.com[:/]##')
OWNER=${REPO%/*}
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)
```

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
   base64 -i ~/Desktop/retext-developer-id.p12 | gh secret set MACOS_CERT_P12_BASE64 --repo "$REPO"
   gh secret set MACOS_CERT_PASSWORD --repo "$REPO"
   gh secret set APPLE_ID --repo "$REPO"
   gh secret set APPLE_TEAM_ID --repo "$REPO"
   gh secret set APPLE_APP_PASSWORD --repo "$REPO"
   ```
   Expected: `gh secret list --repo "$REPO"` lists all five.

3. Move the `.p12` out of `~/Desktop` into wherever you keep key backups. It holds the private key.

### Homebrew tap

1. Create the public repository `$OWNER/homebrew-tap` on GitHub and clone it. `TAP` is the folder of the clone; any folder works, set the same one again in [Per release](#per-release).
   ```bash
   TAP=../homebrew-tap
   gh repo create $OWNER/homebrew-tap --public --description "Homebrew casks"
   gh repo clone $OWNER/homebrew-tap "$TAP"
   mkdir -p "$TAP/Casks"
   ```
   Expected: an empty clone with a `Casks` folder. Fill it on the first release (see [Update the Homebrew cask](#update-the-homebrew-cask)).

## Per release

Tags up to `v1.3.0` predate this script and their sources have no icon or release script, so they can't be built this way. Set the version being released and the tap folder once per shell; every command below uses them.

```bash
VERSION=X.Y.Z
TAP=../homebrew-tap
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

3. Release with GitHub Actions (needs the secrets above). Pushing the tag doesn't start the workflow; run it by hand for the tag. `scripts/release.sh` without `--skip-notarize` also works locally to test notarization, but don't upload its DMG: the workflow publishes the assets.
   ```bash
   git tag "v$VERSION"
   git push origin "v$VERSION"
   gh workflow run release.yml --repo "$REPO" -f tag="v$VERSION"
   sleep 10
   gh run watch --repo "$REPO" "$(gh run list --repo "$REPO" --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')"
   ```
   Expected: the run ends green and the release `v$VERSION` has `Retext-$VERSION.dmg` and `Retext-$VERSION.dmg.sha256`. Edit the generated release notes on GitHub if needed. A re-run skips the build when the release already has the DMG; to rebuild it, delete both assets from the release first.

4. Check what users download.
   ```bash
   curl -fL -o "/tmp/Retext-$VERSION.dmg" "https://github.com/$REPO/releases/download/v$VERSION/Retext-$VERSION.dmg"
   spctl -a -vvv -t install "/tmp/Retext-$VERSION.dmg"
   xcrun stapler validate "/tmp/Retext-$VERSION.dmg"
   ```
   Expected: `accepted`, `source=Notarized Developer ID`, and `The validate action worked!`.

## Update the Homebrew cask

`Casks/retext.rb` in this repository is the template; the tap holds the live copy.

1. Put the release's version and SHA-256 into the template and copy it to the tap.
   ```bash
   SHA=$(curl -fsL "https://github.com/$REPO/releases/download/v$VERSION/Retext-$VERSION.dmg.sha256" | cut -d' ' -f1)
   echo "$SHA"
   sed -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
       -e "s#hlebtkachenko/retext#$REPO#g" -e "s#^  homepage \".*\"#  homepage \"https://$OWNER.github.io/${REPO#*/}/\"#" \
       -e "s/dev\.hapd\.retext/$BUNDLE_ID/g" \
       Casks/retext.rb > "$TAP/Casks/retext.rb"
   ```
   Expected: a 64-character hex hash, and the tap's `Casks/retext.rb` shows the new version and hash, with this repository's download URL, Pages homepage and bundle id (in `uninstall quit:` and the preferences `zap` path; the `co.hleb.retext` line stays, it is upstream's old bundle id).

2. Publish, then audit and install from the tap.
   ```bash
   git -C "$TAP" add Casks/retext.rb
   git -C "$TAP" commit -m "feat: retext $VERSION"
   git -C "$TAP" push
   brew tap $OWNER/tap && brew update
   brew audit --cask --strict --online $OWNER/tap/retext
   brew install --cask $OWNER/tap/retext
   ```
   Expected: the push succeeds, the audit prints nothing (fix the template and repeat on findings), and the install puts `Retext.app` in `/Applications`. Anyone can then run `brew install --cask $OWNER/tap/retext`.

## After the first DMG: GitHub Pages

Do this once, after the first signed DMG is published.

1. In `docs/index.html`, point the hero button at the latest release's DMG and add the `brew install --cask $OWNER/tap/retext` line under it (the `.brew` style is still in the page); update the Install section of `README.md` and `llms.txt` the same way. Commit on `main`.

2. Repository Settings → Pages → Build and deployment → Source: Deploy from a branch → Branch: `main`, folder `/docs` → Save. Or:
   ```bash
   gh api -X POST repos/$REPO/pages -f "source[branch]=main" -f "source[path]=/docs"
   ```
   Expected: after a minute, `https://$OWNER.github.io/${REPO#*/}/` shows the landing page (`docs/index.html`).

3. Repository Settings → General → Social preview → Edit → upload `docs/images/social-preview.png`. GitHub has no API for this.

## App icon

The icon is a Liquid Glass layered icon: the Icon Composer document `Resources/AppIcon.icon`. Its `icon.json` sets the brand-blue (#0F2E66) fill and one glass group (specular highlights, shadow, light translucency) holding two white layers, `Assets/R.svg` (SF Pro Bold R) and `Assets/Cursor.svg` (text cursor). `build.sh` and `scripts/release.sh` compile it with `xcrun actool` into `Contents/Resources/Assets.car` (`CFBundleIconName`), and fail the build if actool can't (it needs Xcode 26 or later). You can open and tune the document in Icon Composer (`/Applications/Xcode.app/Contents/Applications/Icon Composer.app`).

`scripts/make-icon.swift` writes the two SVG layers, compiles the document, and from the system's glass render writes `Resources/AppIcon.icns` (the `CFBundleIconFile` fallback), `docs/images/icon-240.png` (Product Hunt thumbnail) and `docs/images/social-preview.png` (1280x640, GitHub and Open Graph). The brand colours are constants at the top of that script. Re-run it after changing the glyphs or `icon.json`:

```bash
swift scripts/make-icon.swift
```

Expected: `Wrote .../Resources/AppIcon.icon/Assets/R.svg, Cursor.svg, .../Resources/AppIcon.icns and docs/images/icon-240.png, social-preview.png`.

## What the release script does

1. Checks that `VERSION` equals `CFBundleShortVersionString`, that `RETEXT_RELEASE_IDENTITY` is set, and, unless `--skip-notarize`, that `RETEXT_NOTARY_PROFILE` is set. It stops before building otherwise.
2. Builds a universal (arm64 and x86_64) release binary and lays out `Retext.app` like `build.sh`, in a fresh temporary folder.
3. Signs the app with `--options runtime --timestamp`, notarizes a zip of it and staples the ticket to the app.
4. Builds the DMG (volume `Retext`, the app plus an `Applications` link), signs it, notarizes it and staples it.
5. Verifies with `stapler validate` and `spctl -a -vvv -t install`, then writes `build/Retext-VERSION.dmg` and `build/Retext-VERSION.dmg.sha256`.

`RETEXT_NOTARY_KEYCHAIN` (optional) names the keychain that holds the notary profile; the workflow sets it to its temporary keychain.
