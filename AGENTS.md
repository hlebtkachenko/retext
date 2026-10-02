# Retext

Native macOS menu-bar app: select text anywhere, press ⌥Space and type an instruction or pick an action (Fix grammar, English, a translation into the Mac's language, or your own), or press ⌥1…⌥9 directly; the selection is replaced in place via `claude -p` (the `haiku` alias for short grammar fixes, `sonnet` otherwise). Uses your own Claude Code login: subscription usage counts against your plan's limits; API-key logins are billed to your account.

- Stack: Swift 6 package (language mode 5), SwiftUI + Liquid Glass (macOS 26+), AppKit NSPanel, CGEvent tap for shortcuts, Accessibility API. No dependencies.
- Targets: `RetextCore` (pure logic: settings, routing, prompts, cache key, history, usage; tested), `Retext` (the app), `RetextCoreTests` (Swift Testing).
- Data: `~/Library/Application Support/Retext/` holds `settings.json`, `history.json` (cache + Recent, last 20), `usage.json` (per day).
- Build and install: `./build.sh` (installs to `~/Applications`). `./build.sh --no-install` builds only. Signing identity: `$RETEXT_SIGN_IDENTITY`, else the untracked `.sign-identity` file (one line, the identity name), else ad-hoc (`-`). A real identity keeps the Accessibility grant across rebuilds; ad-hoc builds lose it each time. Never commit an identity name.
- UI preview without a selection: `build/Retext.app/Contents/MacOS/Retext --demo menu|working|done|error|empty|nochange`, or `--demo settings [actions|app|protected|engine|general|usage]`. Demo prints the `screencapture` rectangle or window number.
- Gate: `swift build` and `swift test` must pass; check UI changes with `--demo` screenshots.
- E2E with synthetic keys: confirm the frontmost app and document are your own scratch TextEdit or Preview file before every keystroke.
- See ARCHITECTURE.md for the flow.
