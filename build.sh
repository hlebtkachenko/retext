#!/bin/bash
# Builds build.noindex/Retext.app, signs it and installs it to ~/Applications. Usage: ./build.sh [--no-install]
# Signing identity: $RETEXT_SIGN_IDENTITY, else the contents of .sign-identity (untracked), else "-" (ad-hoc).
# A real identity keeps the Accessibility grant across rebuilds; ad-hoc builds lose it on every rebuild.
set -euo pipefail
cd "$(dirname "$0")"

identity="${RETEXT_SIGN_IDENTITY:-$(cat .sign-identity 2>/dev/null || echo -)}"
aside="build.noindex/replaced/$(date +%Y%m%d-%H%M%S)"
files() { (cd "$1" && find . \( -type f -o -type l \) | sort); }
# Moves files in bundle $1 that are not listed in $2 to $aside/$3 (never deleted): a build or install replaces
# the app's contents instead of merging into them, so a file a newer version dropped can't linger and get sealed.
# User data (Application Support, preferences, Keychain, Accessibility grant) lives outside the bundle and is kept.
prune() {
    comm -23 <(files "$1") "$2" | while IFS= read -r f; do
        mkdir -p "$aside/$3/$(dirname "$f")"
        mv "$1/$f" "$aside/$3/$f"
        echo "Moved stale $1/${f#./} to $aside/$3" >&2
    done
}
swift build -c release
# .noindex keeps Spotlight from indexing the build copy and offering it as a second Retext.
app=build.noindex/Retext.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Retext "$app/Contents/MacOS/Retext"
cp Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# The Liquid Glass icon: compile the Icon Composer document into a fresh directory, so a stale Assets.car can't ship.
icon=$(mktemp -d "${TMPDIR:-/tmp}/retext-icon.XXXXXX")
xcrun actool Resources/AppIcon.icon --compile "$icon" --platform macosx --minimum-deployment-target 26.0 \
    --app-icon AppIcon --output-partial-info-plist "$icon/partial.plist" >/dev/null
[[ -s "$icon/Assets.car" ]] || { echo "actool did not compile Resources/AppIcon.icon (needs Xcode 26 or later)." >&2; exit 1; }
cp "$icon/Assets.car" "$app/Contents/Resources/Assets.car"
printf '%s\n' ./Contents/Info.plist ./Contents/MacOS/Retext ./Contents/Resources/AppIcon.icns \
    ./Contents/Resources/Assets.car ./Contents/_CodeSignature/CodeResources | sort > "$icon/expected"
prune "$app" "$icon/expected" build
codesign --force --options runtime --sign "$identity" "$app"
if [[ "$identity" == "-" ]]; then
    echo "Signed ad-hoc: grant Accessibility to Retext again after installing (see .sign-identity in AGENTS.md)." >&2
fi

[[ "${1:-}" == "--no-install" ]] && exit 0
pkill -x Retext || true
# Wait for it to quit: a new Retext started while the old one still holds the single-instance lock would exit.
for _ in {1..50}; do pgrep -x Retext >/dev/null || break; sleep 0.1; done
pgrep -x Retext >/dev/null && { echo "Retext is still running; quit it and run ./build.sh again." >&2; exit 1; }
ditto "$app" ~/Applications/Retext.app
files "$app" > "$icon/built"
prune ~/Applications/Retext.app "$icon/built" installed
codesign --verify --strict ~/Applications/Retext.app
# An Accessibility entry made for an older build (an ad-hoc one is pinned to that exact binary) stays switched on in
# System Settings but no longer applies, and switching it off and on keeps it. Reading the database needs Full Disk
# Access for this terminal; without it, or on an ad-hoc build (which never matches a good entry), the check is skipped.
tccdb="/Library/Application Support/com.apple.TCC/TCC.db"
if [[ "$identity" != "-" ]] && sqlite3 "$tccdb" "select writefile('$icon/tcc-req', csreq) from access where service = 'kTCCServiceAccessibility' and client = 'dev.hapd.retext'" >/dev/null 2>&1 \
    && [[ -s "$icon/tcc-req" ]]; then
    req=$(csreq -r "$icon/tcc-req" -t 2>/dev/null || true)
    if [[ -n "$req" ]] && ! codesign --verify -R="$req" ~/Applications/Retext.app 2>/dev/null; then
        echo "Accessibility is set for an older Retext build and won't apply to this one. Run" >&2
        echo "  tccutil reset Accessibility dev.hapd.retext" >&2
        echo "then allow Retext when it asks." >&2
    fi
fi
# Forget the build copies (and the old build/ one) so "Open at login" (SMAppService) resolves to the installed app.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u "$PWD/$app" 2>/dev/null || true
"$lsregister" -u "$PWD/build/Retext.app" 2>/dev/null || true
"$lsregister" -f ~/Applications/Retext.app
# Launch Services can refuse the first open right after re-registering (-600); retry once.
open ~/Applications/Retext.app || { sleep 1; open ~/Applications/Retext.app; }
