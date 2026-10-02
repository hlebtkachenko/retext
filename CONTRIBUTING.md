# Contributing to Retext

Thanks for helping. Retext is a small, dependency-free macOS app; changes that keep it that way are the easiest to accept.

## Before you start

- **Bugs:** open an issue with the bug template: macOS version, Claude Code version (`claude --version`), the app you were in, and what happened.
- **Features:** open an issue first for anything larger than a small fix, so we can agree on the shape before you build it.
- **Security issues:** don't open a public issue; see [SECURITY.md](SECURITY.md).

## Development

Requirements: macOS 26+, Xcode 26+, and Claude Code installed and logged in (for end-to-end checks).

```sh
swift build          # debug build
swift test           # RetextCore tests (Swift Testing)
./build.sh           # release build, sign, install to ~/Applications, launch
./build.sh --no-install
```

- `Sources/RetextCore`: pure logic (settings, routing, prompts, cache key, history, usage). New logic goes here, with tests in `Tests/RetextCoreTests`.
- `Sources/Retext`: the app (event tap, Accessibility, popup, settings window).
- UI changes: check them with `build/Retext.app/Contents/MacOS/Retext --demo menu` (or `working`, `done`, `error`, `nochange`, `settings <pane>`) and include a screenshot in the pull request.
- [ARCHITECTURE.md](ARCHITECTURE.md) explains the flow from shortcut to paste; [AGENTS.md](AGENTS.md) holds the conventions for AI coding agents and humans alike.

## Pull requests

- One logical change per pull request; [Conventional Commits](https://www.conventionalcommits.org) for commit messages (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).
- `swift build` and `swift test` must pass (CI runs both).
- No third-party dependencies without discussing it in an issue first.
- Update README, ARCHITECTURE.md and CHANGELOG.md when behaviour or setup changes.

By contributing, you agree that your contributions are licensed under the [Apache License 2.0](LICENSE) and that you follow the [Code of Conduct](CODE_OF_CONDUCT.md).
