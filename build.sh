#!/bin/bash
# Builds Retext.app, signs it and installs it to ~/Applications. Usage: ./build.sh [--no-install]
# Signing identity: $RETEXT_SIGN_IDENTITY, else the contents of .sign-identity (untracked), else "-" (ad-hoc).
# A real identity keeps the Accessibility grant across rebuilds; ad-hoc builds lose it on every rebuild.
set -euo pipefail
cd "$(dirname "$0")"

identity="${RETEXT_SIGN_IDENTITY:-$(cat .sign-identity 2>/dev/null || echo -)}"
swift build -c release
app=build/Retext.app
mkdir -p "$app/Contents/MacOS"
cp .build/release/Retext "$app/Contents/MacOS/Retext"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --options runtime --sign "$identity" "$app"

[[ "${1:-}" == "--no-install" ]] && exit 0
pkill -x Retext || true
ditto "$app" ~/Applications/Retext.app
# Forget the build copy so "Open at login" (SMAppService) resolves to the installed app, not build/.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u "$PWD/$app" 2>/dev/null || true
"$lsregister" -f ~/Applications/Retext.app
# Launch Services can refuse the first open right after re-registering (-600); retry once.
open ~/Applications/Retext.app || { sleep 1; open ~/Applications/Retext.app; }
