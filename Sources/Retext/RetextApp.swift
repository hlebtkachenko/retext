import Carbon.HIToolbox
import RetextCore
import SwiftUI

@main
struct RetextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra(isInserted: showIcon) {
            // Clicking an action runs it on the selection in the app in front, like its ⌥N shortcut.
            ForEach(Array(state.settings.actions.enumerated()), id: \.element.id) { index, action in
                Button { delegate.controller.trigger(index) } label: { Label(action.title, systemImage: action.symbol) }
                    .keyboardShortcut(index < 9 ? KeyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .option) : nil)
            }
            Divider()
            Menu("Copy Recent") {
                if state.history.entries.isEmpty { Text("Nothing yet") }
                ForEach(state.history.entries) { entry in
                    Button(Self.short(entry)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.output, forType: .string)
                    }
                }
            }
            Divider()
            // Shown only when something blocks Retext (each opens the place that fixes it) or an update is out.
            if hasProblemRows {
                if !delegate.hotkeyOK {
                    Button("Allow Accessibility…", systemImage: "exclamationmark.triangle") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
                if let problem = state.providerStatus?.problem {
                    Button(problem, systemImage: "exclamationmark.triangle") { SettingsWindow.shared.show(.engine) }
                }
                if let update = availableUpdate {
                    Button("Update available: \(update.version)…", systemImage: "arrow.down.circle") { NSWorkspace.shared.open(update.page) }
                }
                Divider()
            }
            Button("Check for Updates…") { AppState.shared.checkForUpdatesInSettings() }
            Button("Settings…") { SettingsWindow.shared.show() }.keyboardShortcut(",")
            Divider()
            Button("Quit Retext") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        // The main menu shown while Settings or Welcome is open: About Retext, Check for Updates…, Settings… ⌘, in the
        // app menu (Settings is Retext's own window, not a SwiftUI Settings scene), Welcome to Retext in Help.
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { AppState.shared.checkForUpdatesInSettings() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindow.shared.show() }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .help) {
                Button("Welcome to Retext") { WelcomeWindow.shared.show() }
            }
        }
    }

    private var hasProblemRows: Bool {
        !delegate.hotkeyOK || state.providerStatus?.problem != nil || availableUpdate != nil
    }

    /// The newer release the menu offers, when update checks are on.
    private var availableUpdate: (version: String, page: URL)? {
        guard state.settings.checkForUpdates, let update = state.update, let page = URL(string: update.html_url) else { return nil }
        return (update.version, page)
    }

    /// SwiftUI writes isInserted back on every scene update; writing only real changes keeps that from
    /// re-publishing settings and looping (a frozen main thread at full CPU).
    private var showIcon: Binding<Bool> {
        Binding(get: { state.settings.showMenuBarIcon },
                set: { if $0 != state.settings.showMenuBarIcon { state.settings.showMenuBarIcon = $0 } })
    }

    /// "Fix grammar · Mail: Teh quick brown…" for the Recent submenu; clicking copies the output.
    private static func short(_ entry: HistoryEntry) -> String {
        let input = RetextCore.Engine.normalize(entry.input)
        return "\(entry.title.prefix(24)) · \(entry.appName): \(input.prefix(40))\(input.count > 40 ? "…" : "")"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let controller = PopupController()
    @Published var hotkeyOK = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A `claude` that exits before reading a large selection must not kill Retext.
        signal(SIGPIPE, SIG_IGN)
        if let i = CommandLine.arguments.firstIndex(of: "--provider-smoke") { return providerSmoke(Array(CommandLine.arguments.dropFirst(i + 1))) }
        if let i = CommandLine.arguments.firstIndex(of: "--demo") {
            let state = CommandLine.arguments.dropFirst(i + 1).first ?? "menu"
            if state == "settings" {
                let pane = CommandLine.arguments.dropFirst(i + 2).first ?? ""
                // The case name (styles, words) or the start of the title (app, protected).
                SettingsView.initialPane = SettingsView.Pane.allCases.first { "\($0)" == pane || $0.rawValue.lowercased().hasPrefix(pane) } ?? .overview
                SettingsWindow.shared.show()
                print("window \(SettingsWindow.shared.window?.windowNumber ?? 0)")  // for screencapture -l
                fflush(stdout)
                return
            }
            if state == "welcome" {
                WelcomeWindow.shared.isDemo = true
                WelcomeWindow.shared.show()
                print("window \(WelcomeWindow.shared.window?.windowNumber ?? 0)")
                fflush(stdout)
                return
            }
            controller.demo(state)
            return
        }
        // The value of kAXTrustedCheckOptionPrompt, a C global var that Swift 6 treats as shared mutable state.
        let prompt = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        Hotkeys.menu = { [weak self] in self?.controller.trigger() }
        Hotkeys.action = { [weak self] index in self?.controller.trigger(index) }
        Hotkeys.configure(AppState.shared.settings)
        AppState.shared.checkProvider()
        startHotkeys()
        // Electron apps expose their selection only after AXManualAccessibility is set. With "Improve Electron app
        // support" on, set it on every app switch so the ⌥N selection check in the event tap works there before the
        // first ⌥Space; with it off, the tap and SelectionIO.read() set it only when they read.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // queue: .main delivers on the main thread.
            MainActor.assumeIsolated {
                if Hotkeys.electronOnSwitch, let app { SelectionIO.enableElectronAccessibility(app) }
            }
        }
        if Hotkeys.electronOnSwitch, let app = NSWorkspace.shared.frontmostApplication { SelectionIO.enableElectronAccessibility(app) }
        if !AppState.shared.settings.onboarded { WelcomeWindow.shared.show() }
        AppState.shared.update = UpdateChecker.available
        UpdateChecker.checkIfDue()
        // A Mac that sleeps instead of quitting would otherwise check only once. The network is often not back right
        // at wake, and a failed check is retried only at the next launch or wake, so wait a little first.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(30))
                UpdateChecker.checkIfDue()
            }
        }
    }

    /// `--provider-smoke <claude|chatgpt|custom> <medium|high|max>`: one Fix grammar run on a fixed text through the runner
    /// (no cache, no history, settings.json untouched), printed, then exit. Custom reads RETEXT_SMOKE_BASE_URL,
    /// RETEXT_SMOKE_MODEL and RETEXT_SMOKE_KEY (optional) instead of the saved settings and the Keychain.
    private func providerSmoke(_ args: [String]) {
        guard let provider = args.first.flatMap(Provider.init(rawValue:)), let level = args.dropFirst().first.flatMap(Level.init(rawValue:)) else {
            print("usage: --provider-smoke claude|chatgpt|custom medium|high|max")
            exit(2)
        }
        var settings = AppState.shared.settings
        settings.provider = provider
        let env = ProcessInfo.processInfo.environment
        if provider == .custom {
            settings.custom.baseURL = env["RETEXT_SMOKE_BASE_URL"] ?? settings.custom.baseURL
            if let model = env["RETEXT_SMOKE_MODEL"] { settings.custom.models[level] = ProviderModel(model: model) }
        }
        let action = RetextSettings.defaultActions(languages: ["en"])[0]
        let text = "I has two cat."
        let job = Engine.job(for: action, level: level, text: text, settings: settings, bundleID: nil)
        Task {
            let start = Date()
            do {
                let output = try await ProviderRunner.run(job, text: text, settings: settings, timeout: level.timeout,
                                                          apiKey: { _ in provider == .custom ? env["RETEXT_SMOKE_KEY"] : nil })
                print("OK \(provider.rawValue) \(level.rawValue) \(job.model)/\(job.effort) \(String(format: "%.1f", Date().timeIntervalSince(start))) s, "
                      + "\(output.inputTokens) in, \(output.outputTokens) out: \(output.text)")
                exit(0)
            } catch {
                let failure = error as? ClaudeFailure ?? .other("\(error)")
                print("FAIL \(provider.rawValue) \(level.rawValue) \(job.model)/\(job.effort): \(failure) | \(failure.message(for: provider))")
                exit(1)
            }
        }
    }

    /// Opening Retext while it runs (Finder, Spotlight) shows Settings, the way back when the menu-bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return false
    }

    /// The tap needs the Accessibility grant; retry until it is given so no relaunch is needed.
    private func startHotkeys() {
        hotkeyOK = Hotkeys.start()
        if !hotkeyOK { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startHotkeys() } }
    }
}

/// ⌥-key shortcuts via a session event tap. The tap sees keys before other apps' hotkeys
/// (another app may also register ⌥Space). The bar shortcut (⌥Space or ⌃⌥Space) is always taken. ⌥1…⌥N are taken only when the frontmost app has
/// selected text, so layouts where ⌥digit types a character (Czech ⌥2 = @) keep working everywhere else.
@MainActor
enum Hotkeys {
    static var menu: (@MainActor () -> Void)?
    static var action: (@MainActor (Int) -> Void)?
    static var actionCount = 0
    /// ⌥ or ⌃⌥, with Space, opens the bar.
    static var menuModifiers = CGEventFlags.maskAlternate
    /// Mirrors "Improve Electron app support".
    static var electronOnSwitch = true
    /// Set only while a "Copied" bubble is visible: ⌘Z then restores the previous clipboard instead of reaching the app.
    static var undo: (@MainActor () -> Void)?
    private static var tap: CFMachPort?
    private static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    /// Mirrors the settings the tap reads; called at launch and on every settings change.
    static func configure(_ settings: RetextSettings) {
        actionCount = settings.actions.count
        menuModifiers = settings.menuShortcut == .controlOptionSpace ? [.maskControl, .maskAlternate] : .maskAlternate
        electronOnSwitch = settings.electronSupport
    }

    static func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, _ in
            let modifiers = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            // The tap's run-loop source is on the main run loop (see below), so this callback runs on the main thread.
            let swallow = MainActor.assumeIsolated { Hotkeys.handle(type: type, modifiers: modifiers, key: key, autorepeat: autorepeat) }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }, userInfo: nil) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        return true
    }

    /// Whether the tap swallows the key; a matching shortcut is run on the next main-loop turn.
    private static func handle(type: CGEventType, modifiers: CGEventFlags, key: Int, autorepeat: Bool) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if let undo, modifiers == .maskCommand, key == kVK_ANSI_Z {
            self.undo = nil
            DispatchQueue.main.async(execute: undo)
            return true
        }
        let fire: (@MainActor () -> Void)?
        if key == kVK_Space, modifiers == menuModifiers {
            fire = menu
        } else if modifiers == .maskAlternate, let index = digits.firstIndex(of: key), index < actionCount,
                  frontmostHasSelection(), let action {
            fire = { action(index) }
        } else {
            fire = nil
        }
        guard let fire else { return false }
        if !autorepeat { DispatchQueue.main.async(execute: fire) }
        return true
    }

    /// Non-empty AXSelectedText in the frontmost app's focused element. Short AX timeouts keep the tap from stalling.
    private static func frontmostHasSelection() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return false }
        if !electronOnSwitch { SelectionIO.enableElectronAccessibility(app) }
        guard let element = SelectionIO.focusedElement(of: app, timeout: 0.1) else { return false }
        return !(SelectionIO.selectedText(element) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The menu-bar icon: SF Symbols' character.cursor.ibeam ("A" and a text cursor) with an "R" in place of the "A".
/// SF Symbols has no "R" variant, so the symbol's cursor is kept and the "R" is SF Pro's glyph scaled to the "A"'s
/// height, drawn at every scale (crisp at 1x and 2x) as a template the menu bar tints for light and dark.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let symbol = NSImage(systemSymbolName: "character.cursor.ibeam", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        guard let symbol else { return NSImage() }
        // One point taller, drawn at the top: the menu bar centers this image, while it places the symbol itself half a
        // point higher (checked side by side).
        let image = NSImage(size: NSSize(width: symbol.size.width, height: symbol.size.height + 1), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let rect = CGRect(x: 0, y: 1, width: symbol.size.width, height: symbol.size.height)
            // The "A"'s box and where the cursor starts, in points of the 13 pt symbol (16 x 16), measured from its render.
            let letter = NSRect(x: 1.9, y: 3.05, width: 7.4, height: 9.9), cursorX: CGFloat = 9.5
            let font = NSFont.systemFont(ofSize: 100, weight: .regular) as CTFont
            var character: UniChar = 0x52, glyph: CGGlyph = 0  // "R"
            guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
                  let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return false }
            let box = path.boundingBoxOfPath, scale = letter.height / box.height
            // Right-aligned to the "A"'s box keeps the symbol's gap to the cursor; a whole-point left edge keeps the
            // stem on the pixel grid.
            let left = (letter.maxX - box.width * scale).rounded()
            context.saveGState()
            context.clip(to: CGRect(x: cursorX, y: rect.minY, width: rect.width - cursorX, height: rect.height))
            symbol.draw(in: rect)
            context.restoreGState()
            context.saveGState()
            defer { context.restoreGState() }
            context.translateBy(x: left, y: rect.minY + letter.minY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Retext"
        return image
    }()
}
