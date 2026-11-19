# Retext

Native macOS menu-bar app: select text anywhere, press ⌥Space and type an instruction or pick an action (Fix grammar, English, a translation into the Mac's language, or your own), or press ⌥1…⌥9 directly; the selection is replaced in place via `claude -p` (quality level Medium = the `haiku` alias, High = `sonnet`, Max = `opus`; every bar starts at the default level from Settings, Up/Down change it for one run, ⌥N runs at the default level). Uses your own Claude Code login: subscription usage counts against your plan's limits; API-key logins are billed to your account.

- Stack: Swift 6 package (language mode 6), SwiftUI + Liquid Glass (macOS 26+), AppKit NSPanel, CGEvent tap for shortcuts, Accessibility API. No dependencies.
- Targets: `RetextCore` (pure logic: settings, routing, prompts, cache key, history, usage; tested), `Retext` (the app), `RetextCoreTests` (Swift Testing).
- Data: `~/Library/Application Support/Retext/` holds `settings.json`, `history.json` (cache + Recent, last 20), `usage.json` (per day, last 90 days).
- Build and install: `./build.sh` (installs to `~/Applications` and unregisters `build/Retext.app` from Launch Services, so the login item points to the installed copy; running the build copy registers it again). `./build.sh --no-install` builds only. Signing identity: `$RETEXT_SIGN_IDENTITY`, else the untracked `.sign-identity` file (one line, the identity name), else ad-hoc (`-`). A real identity keeps the Accessibility grant across rebuilds; ad-hoc builds lose it each time. Never commit an identity name.
- UI preview without a selection: `build/Retext.app/Contents/MacOS/Retext --demo menu|working|done|error|empty|nochange|welcome` (`--demo menu max` shows another level), or `--demo settings [actions|styles|words|engine|general|usage]` (the start of the pane title works too: `app`, `protected`). Demo prints the `screencapture` rectangle or window number. The welcome demo never marks Retext as onboarded.
- Gate: `swift build` and `swift test` must pass; check UI changes with `--demo` screenshots.
- E2E with synthetic keys: confirm the frontmost app and document are your own scratch TextEdit or Preview file before every keystroke.
- Release: `scripts/release.sh VERSION`, see docs/RELEASING.md. Never notarize or tag without the owner's go.
- Eval: `python3 -I eval/run.py`. Re-run it after editing prompts or add-ons. It uses the owner's Claude subscription.
- See ARCHITECTURE.md for the flow.
