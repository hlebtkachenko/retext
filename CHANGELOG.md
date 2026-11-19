# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- An app icon.
- A signed and notarized DMG download and a Homebrew cask (`brew install --cask hlebtkachenko/tap/retext`), from 1.4.0.
- A landing page.
- Quality levels Medium (Claude Haiku), High (Claude Sonnet) and Max (Claude Opus). High and Max also add extra instructions. Pick the default level in Settings → Engine; ↑ and ↓ in the bar change it for that run, shown in a chip at the end of the bar.
- "Show in menu bar" in Settings → General hides the menu-bar icon (useful when it sits behind the notch). With it off, open Retext again from Spotlight or Finder to get to Settings.
- A welcome window on first launch checks the Accessibility permission and Claude Code and has a sample text to try Retext on. Open it again from the menu (Welcome…) or Settings → General.
- Settings → General shows the Accessibility and Claude Code status live, with a button that opens the Accessibility settings.
- Export and import settings as JSON, and reset all settings to their defaults (Settings → General → Backup). Importing keeps this Mac's Claude Code path.
- Reset Prompt puts back the built-in prompt of a Grammar or Translate action, and Restore Default Actions brings back the default actions.
- Test Claude Code in Settings → Engine sends one tiny request and shows the Claude Code version, or what went wrong.
- Paste a list of protected words, one per line or separated by commas; the add field also takes several terms separated by commas.
- Update check: at most once a day, at launch and when the Mac wakes, Retext asks GitHub for the latest release and shows "Update available" in the menu when there is a newer one. Turn it off with "Check for updates" in Settings → General.
- Settings → General has an About section with the version and a link to GitHub.

### Changed
- The per-action model picker is replaced by the quality levels. ⌥1…⌥9 and typed instructions use the default level, so with Medium they now run on Haiku (actions on Auto and typed instructions used Sonnet before). Model choices in existing settings are ignored.
- The menu-bar menu lists your actions with their ⌥1…⌥9 shortcuts; clicking one runs it on the selected text. The help text is gone.
- Recent says that a click copies the result, and the usage line opens Settings → Usage.
- A missing Accessibility permission or Claude Code shows up in the menu only when it happens, and clicking it opens the place that fixes it.
- Usage statistics keep the last 90 days; older days are dropped.
- App styles: pick the app from a list of running and installed apps, with icons, instead of typing its bundle id.
- Runs at Max may take up to 2 minutes before they time out; Medium and High keep 1 minute.
- Deleting an action, clearing the history, importing and resetting settings ask for confirmation first.
- Action rows and Remove buttons in Settings can be reached with the keyboard and VoiceOver. An SF Symbol name that doesn't exist shows a warning.
- "Improve Electron app support" moved to a new Advanced section in Settings → General. Settings → Actions explains that ⌥N follows the list order and what each kind does.

### Fixed
- Mail: results are pasted into the message again instead of only copied, and ⌥1…⌥9 work in the message body.
- A selection that contains an image or other attachment (such as a Mail signature image) is no longer pasted over, which turned the image into its file name: the result is copied instead, and ⌘Z puts the previous clipboard back.
- ⌥1…⌥9 work on selected text in Safari pages too (the result is copied, since a page can't be edited).
- ⌥1…⌥9 also work in web views that report an empty Accessibility selection, and a selection changed while Claude Code worked is detected there too, so the result is copied instead of pasted over the wrong text.
- Retext no longer quits when Claude Code stops before reading a very large selection.
- ⌥Space shows the bar again when you have no actions, so you can still type an instruction.
- Keys typed in Settings or the welcome window while the bar is open no longer run or cancel the bar.
- Retext no longer crashes at launch when settings.json holds more than nine actions; only the first nine are kept.
- A settings.json that can't be read is copied to settings.json.invalid before Retext starts with the default settings, and the welcome window doesn't open for it or when only the history and usage files are left.
- Esc stops Claude Code even right after you start an action, and pressing a shortcut again straight after Esc no longer runs two jobs at once or leaves one that Esc can't stop.

## [1.3.0] - 2026-10-05

### Changed
- Translations convey meaning instead of word-by-word wording: native word order and phrasing, no constructions carried over from the source language, register kept.
- Fix grammar also rewrites phrasing a native speaker wouldn't use, and leaves already-natural text and casual style untouched.
- Clearer "Edit as" instructions: no invented facts, reasons or commitments; the text's language is kept unless the instruction asks for another.
- Actions on Auto use Claude Sonnet; the Haiku threshold is removed. Haiku can still be chosen per action.
- No default app style: Retext only rewrites the selected text.
- Saved actions that still have the 1.2.0 default prompts move to the new ones; edited prompts are kept.

### Added
- Grammar fixes and translations keep a one-line text on one line, and a grammar result with extra text (such as a note to you) is not pasted.

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

[1.3.0]: https://github.com/hlebtkachenko/retext/releases/tag/v1.3.0
[1.2.0]: https://github.com/hlebtkachenko/retext/releases/tag/v1.2.0
