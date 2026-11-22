# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org).

## [1.5.0] - 2026-11-22

### Added
- A redesigned Settings window with a unified toolbar. The sidebar starts with a Retext row (app icon, name and "About", or "Update Available") that opens About (where Settings opens at launch), followed by General, Actions, Per-App Styles, Protected Words, AI (was Engine) and History. The window's title is the open pane's name; Back and Forward in the toolbar (⌘[ and ⌘]) step through the panes you opened, and each pane starts with a one-line description (About shows it in the hero, under the name). Pop-up and pull-down buttons are bordered, as in System Settings, and row icons are tinted symbols on a neutral tile.
- Settings → About (replaces the About section in General): the version, an Onboarding row, Accessibility and provider status (Grant Access…), Updates ("Check for Updates Automatically", the last check with Check Now, and a card for a newer release with Open Release Page and the `git pull && ./build.sh` command), and links to the website (retext.hapd.dev), the GitHub repository, the changelog and the issue tracker.
- Onboarding replaces the welcome window: four steps (welcome, Accessibility with live status and Grant Access…, the AI provider with its status and a Test, and the bar shortcut with a sample text to try it on). It opens on first launch, from the Onboarding row in Settings → About and from Help → Retext Onboarding. On a new install, Retext asks for Accessibility in Onboarding instead of at launch.
- Settings → History (replaces Usage): Keep (Off, Last 20, Last 60 or Unlimited; Last 20 by default), a Clear History row, Usage (Runs, Tokens and Price for Today, 7 Days, 30 Days or 90 Days), and History (N), a searchable list of results; a click opens a result, its context menu copies or deletes it. A result's details show the full original and result, each with a copy button, Show Changes under the result, the action, app, provider, model, level and effort, tokens, price and duration, and Delete. Lowering Keep below the number of saved results, or turning it off, asks first.
- The bar shortcut: a keycap field in Settings → General; click it to record your own, or pick a preset (⌥Space, ⌃⌥Space, ⌃⇧Space) from its context menu, with a reset to ⌥Space. Shortcuts that would break typing or a system shortcut are refused with the reason: no modifier or only ⇧, ⌘C, ⌘V, ⌘Z, ⌥1…⌥9, ⌘Space, ⌃Space and ⌥⌘Space. Retext's shortcuts are paused while recording.
- "Preview Before Replacing" in Settings → General (off by default), with a live sample: the bar shows the result with the changes marked (inserted words highlighted, deleted ones struck through); Return or the Replace button replaces the selection, Esc or Discard discards the result, ⌘C or Copy copies it. A click elsewhere or a switch to another app discards it; if another app came to the front while Retext worked, the result is copied instead.
- Settings → Actions: drag a row to reorder, with the other rows moving aside as you drag (Move Up and Move Down in its context menu and for VoiceOver); click a row to edit it. An action opens in an editor sheet with its title, icon (20 symbols, with short names for VoiceOver), kind, prompt, an Insert Example menu and Reset Prompt; Cancel leaves the action unchanged.
- Settings → Protected Words: click a word to edit it in place; an edit with several words splits into rows, and an empty or duplicate edit removes the row.
- The menu-bar menu has History… (opens Settings → History). "Check for Updates…" reads "Update Available (x.y.z)…" once a newer release is known; both open Settings → About and check there, regardless of the daily limit and the automatic setting. A 403 from GitHub reads "GitHub rate limit reached. Try again later."
- One Retext runs at a time: opening it again while it runs shows the running copy's Settings (from Terminal it prints "Retext is already running; showing its Settings.").
- The bar refuses selections over 50,000 characters ("Selection too long (over 50,000 characters)"), before any provider call.
- VoiceOver: the bar's selected action is marked, the level chip is adjustable (swipe up or down), the preview buttons read Replace, Discard and Copy, and the outcome and errors are announced.

- Settings → AI → Models for Claude Code: a model (Default, haiku, sonnet, opus or fable) and an effort (Default, low, medium, high, xhigh or max) per level, as for ChatGPT. The model and effort controls of every provider line up in columns at any window width.
- Until Accessibility is allowed, the bar shortcut opens Settings → About, where the Accessibility row shows how to allow it.

### Changed
- Settings → About: the tagline sits in the hero, under "Retext" and above the version, instead of above the hero.
- Settings → AI: the default level is one "Default Effort" row with its picker on the same line, without a section title or icon.
- History keeps the full selected text and result of each run, with the action, app, level, provider, model, effort, tokens, price and duration, in plain text in `history.json`, as many as Keep allows. With Keep set to Off, nothing is written (the file is emptied) and only the last result stays in memory as the cache until Retext quits. At launch, a `history.json` over the limit is trimmed and saved back. History is saved in the background, half a second after the last change, and before Retext quits.
- Settings from an earlier version carry over: "Keep history" on becomes Keep Last 20, off becomes Off, and the ⌥Space or ⌃⌥Space choice is kept. Going back to an earlier Retext afterwards keeps only the 20 newest results (a build from main before this change also shortens each selection to its first 60 characters), turns history on again if it was off, and resets the shortcut to ⌥Space.
- The menu-bar menu: your actions, a red row only when the active provider can't run (it opens Settings → AI), History…, Settings… (⌘,), Check for Updates… and Quit Retext. Recent, the usage line, Welcome… and the Accessibility row are gone. The icon is an "R" with a text cursor (was an "A").
- While Settings or Onboarding is open, the Retext app menu has About Retext (opens Settings → About), Check for Updates… and Settings… (⌘,), and the Help menu has Retext Onboarding.
- Settings → AI: Provider first (the provider, its path, login or key, and Test), then Default Effort (Medium, High, Max side by side) and Models (each level's model and effort; its timeout on hover). Removing the custom API key asks first. Messages that pointed to Settings → Engine now point to Settings → AI.
- Settings → General: sections Startup (Open at Login, Show in Menu Bar, whose hint is now a tooltip), the shortcut, the preview, Back Up Settings (Export… and Import…), Advanced and Reset All Settings. Reset… is red with Cancel as the default button, so Return never resets; reset and import keep history, usage and the Keep setting. Clear History… moved to History.
- Settings → Per-App Styles: each style has a header with the app's icon, name and bundle id, Change App and Remove (−), above its style field.
- Settings: Title Case row titles and buttons and shorter footers (some moved into tooltips). Protected Words: the add field takes several lines (one word per line, or separated by commas). Restore Default Actions… and Delete Action… are red, with Cancel as the default button of their confirmations.
- The provider status in Onboarding and Settings → About shows its path with `~` for the home folder.
- The Accessibility status in Onboarding and Settings → About, while access is off, adds: "If Retext is already listed, remove it with − and add it again."
- The bundle id is now `dev.hapd.retext` (was `co.hleb.retext`), and the custom API key's Keychain service follows it: a key saved by an earlier version is moved there on first use and the old item deleted. macOS ties the Accessibility permission and the login item to the bundle id, so after updating, allow Retext in Accessibility again and turn "Open at Login" on again once if you used it; remove the old Retext entry in System Settings → Privacy & Security → Accessibility (select it and click −). `tccutil reset Accessibility co.hleb.retext` works only before updating, while the old version is still installed. The first custom API run after updating may ask for Keychain access to the old item: allow it so Retext can move the key, or enter the key again in Settings → AI. The preferences domain changes too, so the update-check state starts fresh (settings, history and usage are in Application Support and stay).
- The bar's field placeholder reads "Instruction" (was "Edit as"). In a preview, Replace is an accent-coloured button. After a "Copied" result, ⌘Z shows "Clipboard restored".
- Build: `./build.sh` builds into `build.noindex/Retext.app` (was `build/`), so Spotlight doesn't offer the build copy as a second Retext. It waits for the running Retext to quit, verifies the installed copy's signature and unregisters the build copies from Launch Services. It warns after an ad-hoc signature that Accessibility must be granted again, and `.sign-identity` may hold the SHA-1 hash of a code-signing identity instead of its name, which keeps the name out of the file.
- `--demo` windows open behind other windows, with no Dock icon and without taking focus, and the demo quits after 30 seconds. A demo shows sample settings, history and usage and never reads or writes your files. `--demo settings` takes the new pane names (the old ones still work), `--demo onboarding [welcome|access|provider|shortcut]` shows an Onboarding step, `--demo settings words paste` shows the Paste List sheet, and `--dark` shows dark mode.
- The eval's prompt parity check also covers the High and Max add-ons and stops the run (exit 1) when the prompts drift from the Swift sources.
- A new `RetextTests` test target covers the app's subprocess runner, command lookup, shortcut key codes, the hotkey pause, the shortcut field's keycaps and the GitHub mark.
- Code of Conduct reports go through the repository's private reporting form (Security tab), like security reports, instead of the maintainer's GitHub profile.

### Fixed
- Replacing could do nothing while still showing "Replaced": after the bar closed, macOS kept sending keys to Retext, so its ⌘V never reached the app. The paste now goes straight to the app, the Replaced bubble shows at the text, and a bubble that opens on its own no longer takes the keyboard.
- The bar lines up with the first character of a multi-line selection, also in apps that report only part of the selection's bounds.
- Before Accessibility was allowed, ⌥Space reached the app in front and typed a no-break space over the selection.
- A ChatGPT effort chosen for a level is used even when its model is left at Default; it used to fall back to the built-in effort.
- A Claude Code or Codex run that hangs and ignores the stop is killed 2 seconds later (SIGTERM, then SIGKILL to its process group), and a background job it started can't hold the run open. The login-shell lookup is stopped after 3 seconds the same way.
- A `claude` or `codex` that wasn't found, or whose found path was removed, is looked up again on the next run, so installing or moving it works without relaunching Retext.
- A Claude Code or custom API answer cut off at the model's output limit fails with "The answer was cut off. Your text is unchanged." and is never pasted or cached; the call still counts in the usage.
- After a paste, the previous clipboard comes back 1.5 seconds later (was 0.7), and only if the clipboard still holds Retext's result, so something you copied in between is kept.
- A ⌘C copy that lands after Retext stopped waiting for it is undone too, so your clipboard isn't left holding the selection.
- A second ⌥Space while Retext is still reading the selection is ignored instead of starting another read.
- The preview's diff stays fast on long text.
- The menu's provider status no longer shows an older check's result after a newer one.
- Return starts a new line in an action's prompt editor instead of ending the edit.
- `./build.sh` replaces the app's contents instead of merging into them: a file a newer build no longer has is moved to `build.noindex/replaced/`, never left in the app. Settings, history, preferences and the Keychain key live outside the app and are kept.

## [1.4.0] - 2026-11-20

### Added
- Providers: besides Claude Code, Retext can run on ChatGPT through the Codex CLI (your ChatGPT login; Retext never stores OpenAI credentials) or on any OpenAI-compatible API (OpenRouter, Ollama, LM Studio, Gemini, Mistral, Groq and others), with the API key in the macOS Keychain. Pick one in Settings → Engine; Medium, High and Max map to its models, and ChatGPT models and efforts can be changed per level. The welcome window, Settings → General and the menu show whether the active provider is ready.
- An app icon.
- Quality levels Medium (Claude Haiku), High (Claude Sonnet) and Max (Claude Opus). High and Max also add extra instructions. Pick the default level in Settings → Engine; ↑ and ↓ in the bar change it for that run, shown in a chip at the end of the bar.
- "Show in menu bar" in Settings → General hides the menu-bar icon (useful when it sits behind the notch). With it off, open Retext again from Spotlight or Finder to get to Settings.
- A welcome window on first launch checks the Accessibility permission and the active provider and has a sample text to try Retext on. Open it again from the menu (Welcome…) or Settings → General.
- Settings → General shows the Accessibility and active provider status live, with a button that opens the Accessibility settings.
- Export and import settings as JSON, and reset all settings to their defaults (Settings → General → Backup). Importing keeps this Mac's Claude Code and Codex paths and the custom API base URL.
- Reset Prompt puts back the built-in prompt of a Grammar or Translate action, and Restore Default Actions brings back the default actions.
- Test buttons in Settings → Engine (Test Claude Code, Test ChatGPT, Test API) send one tiny request to that provider and show its version or server, or what went wrong.
- Paste a list of protected words, one per line or separated by commas; the add field also takes several terms separated by commas.
- Update check: at most once a day, at launch and when the Mac wakes, Retext asks GitHub for the latest release and shows "Update available" in the menu when there is a newer one. Turn it off with "Check for updates" in Settings → General.
- Settings → General has an About section with the version and a link to GitHub.

### Changed
- The per-action model picker is replaced by the quality levels. ⌥1…⌥9 and typed instructions use the default level, so with Medium they now run on Haiku (actions on Auto and typed instructions used Sonnet before). Model choices in existing settings are ignored.
- The menu-bar menu lists your actions with their ⌥1…⌥9 shortcuts; clicking one runs it on the selected text. The help text is gone.
- Recent says that a click copies the result, and the usage line opens Settings → Usage.
- A missing Accessibility permission or a problem with the active provider shows up in the menu only when it happens, and clicking it opens the place that fixes it.
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
- ⌥1…⌥9 also work in web views that report an empty Accessibility selection, and a selection changed while the provider worked is detected there too, so the result is copied instead of pasted over the wrong text.
- Retext no longer quits when Claude Code stops before reading a very large selection.
- ⌥Space shows the bar again when you have no actions, so you can still type an instruction.
- Keys typed in Settings or the welcome window while the bar is open no longer run or cancel the bar.
- Retext no longer crashes at launch when settings.json holds more than nine actions; only the first nine are kept.
- A settings.json that can't be read is copied to settings.json.invalid before Retext starts with the default settings, and the welcome window doesn't open for it or when only the history and usage files are left.
- Esc stops the running request even right after you start an action, and pressing a shortcut again straight after Esc no longer runs two jobs at once or leaves one that Esc can't stop.

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

[1.5.0]: https://github.com/hlebtkachenko/retext/releases/tag/v1.5.0
[1.4.0]: https://github.com/hlebtkachenko/retext/releases/tag/v1.4.0
[1.3.0]: https://github.com/hlebtkachenko/retext/releases/tag/v1.3.0
[1.2.0]: https://github.com/hlebtkachenko/retext/releases/tag/v1.2.0
