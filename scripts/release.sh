#!/bin/bash
# Builds a universal Retext.app, signs it with Developer ID (hardened runtime, timestamp), notarizes and staples it,
# packs it into a signed DMG, notarizes and staples the DMG, and verifies the result. See docs/RELEASING.md.
# Planned signed release, not used yet: current releases are a tag and a GitHub release without assets.
# Usage: scripts/release.sh VERSION [--skip-notarize]
#   VERSION must equal CFBundleShortVersionString in Info.plist. --skip-notarize builds an un-notarized DMG for local tests.
# Environment:
#   RETEXT_RELEASE_IDENTITY  Developer ID Application identity (SHA-1 hash or name), required.
#   RETEXT_NOTARY_PROFILE    notarytool keychain profile, required unless --skip-notarize.
#   RETEXT_NOTARY_KEYCHAIN   keychain that holds the profile, optional (CI uses a temporary keychain).
# Output: build/Retext-VERSION.dmg and build/Retext-VERSION.dmg.sha256
set -euo pipefail
cd "$(dirname "$0")/.."

usage="usage: scripts/release.sh VERSION [--skip-notarize]"
version="${1:?$usage}"
notarize=1
case "${2:-}" in
    "") ;;
    --skip-notarize) notarize=0 ;;
    *) echo "$usage" >&2; exit 2 ;;
esac

identity="${RETEXT_RELEASE_IDENTITY:-}"
[[ -n "$identity" ]] || { echo "Set RETEXT_RELEASE_IDENTITY to your Developer ID Application identity (its SHA-1 from: security find-identity -v -p codesigning)." >&2; exit 1; }
plist_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
[[ "$plist_version" == "$version" ]] || { echo "Info.plist has CFBundleShortVersionString $plist_version, not $version. Update Info.plist first." >&2; exit 1; }
if (( notarize )) && [[ -z "${RETEXT_NOTARY_PROFILE:-}" ]]; then
    echo "RETEXT_NOTARY_PROFILE is not set, so the DMG can't be notarized. Create the profile (docs/RELEASING.md, one-time setup) and export RETEXT_NOTARY_PROFILE, or pass --skip-notarize for a local test build." >&2
    exit 1
fi
notary=(--keychain-profile "${RETEXT_NOTARY_PROFILE:-}")
[[ -n "${RETEXT_NOTARY_KEYCHAIN:-}" ]] && notary+=(--keychain "$RETEXT_NOTARY_KEYCHAIN")

# Submits $1 to Apple's notary service and waits; fails unless the status is Accepted.
submit() {
    local out status
    out=$(xcrun notarytool submit "$1" --wait --output-format json "${notary[@]}") || true
    echo "$out"
    status=$(plutil -extract status raw - <<<"$out" 2>/dev/null || echo unknown)
    if [[ "$status" != Accepted ]]; then
        echo "Notarization of $1 ended with status $status. Details: xcrun notarytool log $(plutil -extract id raw - <<<"$out" 2>/dev/null) ${notary[*]}" >&2
        exit 1
    fi
}

archs=(--arch arm64 --arch x86_64)
swift build -c release "${archs[@]}"
bin=$(swift build -c release "${archs[@]}" --show-bin-path)

# Fresh staging directories, so no stale file ends up in the signed bundle or the DMG.
stage=$(mktemp -d "${TMPDIR:-/tmp}/retext-release.XXXXXX")
app="$stage/Retext.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Retext" "$app/Contents/MacOS/Retext"
cp Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# The Liquid Glass icon, compiled from the Icon Composer document (see build.sh).
icon="$stage/icon"
mkdir "$icon"
xcrun actool Resources/AppIcon.icon --compile "$icon" --platform macosx --minimum-deployment-target 26.0 \
    --app-icon AppIcon --output-partial-info-plist "$icon/partial.plist" >/dev/null
[[ -s "$icon/Assets.car" ]] || { echo "actool did not compile Resources/AppIcon.icon (needs Xcode 26 or later)." >&2; exit 1; }
cp "$icon/Assets.car" "$app/Contents/Resources/Assets.car"
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

if (( notarize )); then
    ditto -c -k --keepParent "$app" "$stage/Retext.zip"
    submit "$stage/Retext.zip"
    xcrun stapler staple "$app"
fi

mkdir -p build "$stage/dmg"
dmg="build/Retext-$version.dmg"
ditto "$app" "$stage/dmg/Retext.app"
ln -s /Applications "$stage/dmg/Applications"
hdiutil create -volname Retext -srcfolder "$stage/dmg" -fs HFS+ -format UDZO -ov "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"
codesign --verify --strict --verbose=2 "$dmg"

if (( notarize )); then
    submit "$dmg"
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$app"
    xcrun stapler validate "$dmg"
    spctl -a -vvv -t install "$dmg"
else
    echo "Skipped notarization: Gatekeeper is expected to reject this DMG as unnotarized."
    spctl -a -vvv -t install "$dmg" || true
fi

(cd build && shasum -a 256 "Retext-$version.dmg" | tee "Retext-$version.dmg.sha256")
echo "Built $dmg"
