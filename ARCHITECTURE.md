# Architecture

## Flow
1. `Hotkeys` (a session `CGEvent` tap) always takes the bar shortcut (⌥Space by default, ⌃⌥Space in Settings → General), so it wins over another app's hotkey for the same combo. ⌥1…⌥N (N = number of actions) are taken only when the frontmost app's focused element has non-empty `AXSelectedText` (0.1 s AX timeout); otherwise the key passes through, so Czech ⌥2 = @ still types. The bar shortcut calls `PopupController.trigger()` (menu); ⌥N calls `trigger(index)` and skips the menu (with the menu open, it runs on the selection already read).
2. `SelectionIO.read()` sends ⌘C to get the selected text plus the RTF attributes of its first character, then restores the clipboard; Accessibility on the source app's focused element gives the screen bounds, and the text when ⌘C yields nothing.
3. `PopupController` shows a non-activating `KeyPanel` hosting `PopupView`: a Liquid Glass capsule with an instruction field (focused, an AppKit `NSTextField`) followed by the action buttons, 8 pt below the selection, left-aligned, flipped above when there is no room, under the whole text field when the app's selection bounds are missing or fall outside the field (Electron and web apps), at the mouse pointer when neither is known. The panel takes the hosting view's fitting size and only grows while open. Typing goes to the field; ←/→ move to the buttons only while it is empty; Return runs the instruction or the highlighted button. Electron apps expose their tree only after `AXManualAccessibility` is set: with "Improve Electron app support" on (default), Retext sets it on every app switch so the ⌥N check works before the first bar; off, it is set only when the tap or `SelectionIO.read()` reads. AX calls use a 0.1 to 0.2 s messaging timeout. The original app stays frontmost.
4. `Engine` (RetextCore) builds a `Job`: model (auto: grammar-kind actions under the threshold, default 400 characters, use Haiku; everything else and typed instructions use Sonnet; an explicit model on the action wins) and system prompt (task + editing rules + protected words + the style for the frontmost app's bundle id).
5. Cache: the key is SHA-256 of model + prompt version + system prompt + text. A hit in `history.json` skips Claude and counts as a cache hit (with "Keep history" off, the cache is neither read nor written). Otherwise `ClaudeRunner` runs `claude -p --model haiku|sonnet --output-format json` with user settings, hooks, plugins, MCP and tools disabled; `claude` is the Settings path override, else `command -v claude` in a login shell (once), else the usual install paths. Text goes in on stdin inside a tag with a random suffix (`<text-1a2b3c4d>`), so selected text can't close the block; 60 s timeout, Esc cancels. Failures are sorted from the JSON `result` and stderr into not found, not logged in, usage limit, unknown model or other (`ClaudeFailure`). `result`, tokens and `total_cost_usd` (≈ list price) are recorded in `usage.json` and the history.
6. If the normalized result equals the normalized input, a "No changes needed" bubble shows and nothing is pasted or copied.
7. `SelectionIO.replace()` puts the result on the clipboard as RTF in the original attributes plus plain text (marked transient), re-activates the app, sends ⌘V, then restores the old clipboard, marked `org.nspasteboard.TransientType` so clipboard managers skip it. Rich-text apps keep the original font, size and colour; plain-text fields take the plain string. ⌘Z undoes it.
8. If the selection is read-only (no text role, `AXSelectedText` not settable, no `AXEditableAncestor`: web pages, PDFs, received mail) or changed while Claude worked (checked on the source app, not the system-wide focus, which can be Retext's field), the result is copied instead of pasted. While the "Copied" bubble shows (4 s), the event tap turns ⌘Z into "restore the previous clipboard"; outside that window ⌘Z is untouched.

## Files
- `Sources/RetextCore/Settings.swift`: `RetextSettings` (actions, app styles, protected words, Haiku threshold, bar shortcut, claude path, history and Electron switches), defaults (the third action follows the Mac's first language), JSON load and save, `Store` paths.
- `Sources/RetextCore/Engine.swift`: model routing, system prompt, boundary-tag wrapper, cache key, no-change normalization, `claude -p` JSON parsing, error classification.
- `Sources/RetextCore/History.swift`: history/cache (20 entries) and per-day usage counters.
- `Sources/Retext/RetextApp.swift`: app entry, menu-bar menu (usage line, Recent, Settings…), shortcut event tap.
- `Sources/Retext/AppState.swift`: shared settings, history and usage, saved on change.
- `Sources/Retext/Popup.swift`: state model, SwiftUI view, instruction field, panel, placement, keyboard and click handling, run flow.
- `Sources/Retext/SettingsView.swift`: native settings window (sidebar: Actions, App styles, Protected words, Engine, General, Usage). Engine: Haiku threshold, models, Claude Code path override. General: "Open at login" (reads and sets `SMAppService.mainApp`, off until the user turns it on), bar shortcut, "Improve Electron app support", "Keep history" and Clear History; switches to the `.regular` activation policy while open.
- `Sources/Retext/Selection.swift`: Accessibility read, clipboard fallback, paste.
- `Sources/Retext/Claude.swift`: `claude` discovery and the `claude -p` runner.

## Decisions
- Native app over Hammerspoon: SwiftUI Liquid Glass needs a real app; it also removes a dependency.
- `claude -p` over a built-in API client: Retext never handles credentials. Uses your own Claude Code login: subscription usage counts against your plan's limits; API-key logins are billed to your account. Cost shown is the list-price equivalent.
- Paste via clipboard over AX `setValue`: works in every app and keeps native undo.
- Plain-text paste was dropped: Mail fell back to its default Helvetica instead of the selection's font.
- Event tap over Carbon `RegisterEventHotKey`: Carbon fails when another app holds the combo; the tap takes precedence.
- ⌥digits only with a selection: on Czech and ABC layouts ⌥digits type characters (@, #, ™); swallowing them always broke typing.
- Cache and history share one store capped at 20 entries.
- Instruction field is an `NSTextField`, not a SwiftUI `TextField`: it takes first responder reliably in the non-activating panel.
- No Apple on-device models or Translation: they don't cover every language, and Apple Intelligence isn't available in every system language.
