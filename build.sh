#!/bin/bash
# Builds build.noindex/Retext.app, signs it and installs it to ~/Applications. Usage: ./build.sh [--no-install]
# Signing identity: $RETEXT_SIGN_IDENTITY, else the contents of .sign-identity (untracked), else "-" (ad-hoc).
# A real identity keeps the Accessibility grant across rebuilds; ad-hoc builds lose it on every rebuild.
set -euo pipefail
cd "$(dirname "$0")"

identity="${RETEXT_SIGN_IDENTITY:-$(cat .sign-identity 2>/dev/null || echo -)}"
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
codesign --force --options runtime --sign "$identity" "$app"

[[ "${1:-}" == "--no-install" ]] && exit 0
pkill -x Retext || true
# Wait for it to quit: a new Retext started while the old one still holds the single-instance lock would exit.
for _ in {1..50}; do pgrep -x Retext >/dev/null || break; sleep 0.1; done
pgrep -x Retext >/dev/null && { echo "Retext is still running; quit it and run ./build.sh again." >&2; exit 1; }
ditto "$app" ~/Applications/Retext.app
codesign --verify --strict ~/Applications/Retext.app
# Forget the build copies (and the old build/ one) so "Open at login" (SMAppService) resolves to the installed app.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u "$PWD/$app" 2>/dev/null || true
"$lsregister" -u "$PWD/build/Retext.app" 2>/dev/null || true
"$lsregister" -f ~/Applications/Retext.app
# Launch Services can refuse the first open right after re-registering (-600); retry once.
open ~/Applications/Retext.app || { sleep 1; open ~/Applications/Retext.app; }
