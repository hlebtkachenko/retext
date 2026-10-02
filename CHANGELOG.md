# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org).

## [1.2.0] - 2026-10-02

First public release.

### Added
- ⌥Space bar under the selection with an "Edit as" field for free-form instructions and up to 9 action buttons.
- ⌥1…⌥9 run actions directly, only while text is selected.
- Default actions: Fix grammar, English, and a translation into the Mac's language when it isn't English.
- Custom actions, per-app styles and protected words, edited in a native settings window.
- Model routing through the Claude Code `haiku` and `sonnet` aliases, configurable per action.
- Formatting kept on paste (rich text); read-only selections are copied, and ⌘Z restores the previous clipboard for 4 seconds.
- "No changes needed" check, a cache and Recent menu of the last 20 results, and a daily usage summary.
- Settings for the bar shortcut (⌥Space or ⌃⌥Space), open at login, history, Electron app support and the Claude Code path.
- Clear error messages when Claude Code is missing, not logged in, rate-limited or doesn't know a model.

[1.2.0]: https://github.com/hlebtkachenko/retext/releases/tag/v1.2.0
