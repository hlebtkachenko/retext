import RetextCore
import SwiftUI

/// Takes the single-instance lock before the app starts; `--demo` and `--provider-smoke` run alongside the app.
@main
@MainActor
enum RetextMain {
    static func main() {
        let args = CommandLine.arguments
        if !args.contains("--demo"), !args.contains("--provider-smoke") { SingleInstance.claim() }
        RetextApp.main()
    }
}

/// One Retext at a time: an exclusive flock on Application Support/Retext/instance.lock, held until the process exits
/// (the kernel drops it then, even after a crash). A second launch asks the running one to show Settings and exits.
enum SingleInstance {
    /// Posted by a second launch; the running Retext shows Settings, like opening it again from Finder.
    static let reopen = Notification.Name(Identity.bundleID + ".reopen")
    /// The lock's descriptor: never closed or unlinked, and close-on-exec so provider subprocesses don't inherit it.
    nonisolated(unsafe) private static var lock: Int32 = -1

    static func claim() {
        try? FileManager.default.createDirectory(at: Store.directory, withIntermediateDirectories: true)
        let fd = open(Store.url("instance.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return }  // no lock file: launch normally rather than not at all
        // Retries cover a Retext that is still quitting (a relaunch right after Quit, or build.sh replacing it).
        for attempt in 0...5 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { lock = fd; return }
            guard errno == EWOULDBLOCK else { close(fd); return }
            if attempt < 5 { usleep(200_000) }
        }
        DistributedNotificationCenter.default().postNotificationName(reopen, object: nil, userInfo: nil, deliverImmediately: true)
        FileHandle.standardError.write(Data("Retext is already running; showing its Settings.\n".utf8))
        exit(0)
    }
}

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
            // Shown only when the active provider can't run: red, opens Settings → AI where it is fixed.
            if let problem = state.providerStatus?.problem {
                Button { SettingsWindow.shared.show(.ai) } label: {
                    Image(nsImage: MenuBarIcon.problem)
                    Text(Self.red(problem))
                }
            }
            Button("History…") { SettingsWindow.shared.show(.history) }
            Button("Settings…") { SettingsWindow.shared.show() }.keyboardShortcut(",")
            Button(updateTitle) { AppState.shared.checkForUpdatesInSettings() }
            Divider()
            Button("Quit Retext") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        // The main menu shown while Settings or Onboarding is open: About Retext (Settings → About), Check for Updates…,
        // Settings… ⌘, in the app menu (Settings is Retext's own window, not a SwiftUI Settings scene), Retext
        // Onboarding in Help.
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Retext") { SettingsWindow.shared.show(.about) }
                Button(updateTitle) { AppState.shared.checkForUpdatesInSettings() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindow.shared.show() }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .help) {
                Button("Retext Onboarding") { OnboardingWindow.shared.show() }
            }
        }
    }

    /// "Update Available (x.y.z)…" once a newer release is known; both open Settings → About and check again.
    private var updateTitle: String {
        state.update.map { "Update Available (\($0.version))…" } ?? "Check for Updates…"
    }

    /// The provider problem's menu text in red (menus that ignore the color still show the red symbol).
    private static func red(_ text: String) -> AttributedString {
        var red = AttributedString(text)
        red.foregroundColor = .red
        return red
    }

    /// SwiftUI writes isInserted back on every scene update; writing only real changes keeps that from
    /// re-publishing settings and looping (a frozen main thread at full CPU).
    private var showIcon: Binding<Bool> {
        Binding(get: { state.settings.showMenuBarIcon },
                set: { if $0 != state.settings.showMenuBarIcon { state.settings.showMenuBarIcon = $0 } })
    }

}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let controller = PopupController()
    /// SIGTERM (`pkill`, as build.sh sends, or a logout) skips willTerminate, so the pending history save is flushed here.
    private var terminateSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A `claude` that exits before reading a large selection must not kill Retext.
        signal(SIGPIPE, SIG_IGN)
        if let i = CommandLine.arguments.firstIndex(of: "--provider-smoke") { return providerSmoke(Array(CommandLine.arguments.dropFirst(i + 1))) }
        if let i = CommandLine.arguments.firstIndex(of: "--demo") {
            // A demo runs in the background with no Dock icon, so one left open quits itself. exit, not NSApp.terminate:
            // terminate waits while a sheet or dialog is open. A demo saves nothing, so there is nothing to flush.
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { exit(0) }
            let state = CommandLine.arguments.dropFirst(i + 1).first ?? "menu"
            // `--dark` anywhere after `--demo`: dark mode for screenshots, whatever the Mac's appearance.
            if CommandLine.arguments.dropFirst(i + 1).contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            if state == "settings" {
                let pane = CommandLine.arguments.dropFirst(i + 2).first ?? ""
                SettingsNavigation.shared.pane = SettingsView.Pane(demoName: pane) ?? .about
                if SettingsView.demoExtra == "update" {
                    // `--demo settings about update`: a found release, without asking GitHub.
                    let page = Identity.pageURL(repository: UpdateChecker.repository).appending(path: "releases").absoluteString
                    AppState.shared.update = Release(tag_name: "v9.9.9", html_url: page)
                    AppState.shared.updateCheckResult = .available(AppState.shared.update!)
                }
                SettingsWindow.shared.show()
                print("window \(SettingsWindow.shared.window?.windowNumber ?? 0)")  // for screencapture -l
                fflush(stdout)
                return
            }
            // `--demo onboarding [welcome|access|provider|shortcut]`; `--demo welcome` is the older name.
            if state == "onboarding" || state == "welcome" {
                let step = CommandLine.arguments.dropFirst(i + 2).first.flatMap(OnboardingWindow.Step.init(rawValue:)) ?? .welcome
                AccessibilityRow.demoTrusted = step != .access
                OnboardingWindow.shared.isDemo = true
                OnboardingWindow.shared.show(at: step)
                print("window \(OnboardingWindow.shared.window?.windowNumber ?? 0)")
                fflush(stdout)
                return
            }
            controller.demo(state)
            return
        }
        // A no-op handler, not SIG_IGN: an ignored signal stays ignored in `claude` and `codex`, which are stopped with SIGTERM.
        signal(SIGTERM) { _ in }
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminate.setEventHandler {
            // queue: .main runs the handler on the main thread. Usage is saved on every change; only history waits.
            MainActor.assumeIsolated { AppState.shared.flushHistory() }
            exit(0)
        }
        terminate.resume()
        terminateSource = terminate
        DistributedNotificationCenter.default().addObserver(forName: SingleInstance.reopen, object: nil, queue: .main) { _ in
            // queue: .main delivers on the main thread.
            MainActor.assumeIsolated { SettingsWindow.shared.show() }
        }
        // A new user is asked in Onboarding's Accessibility step; one who finished it and lost the grant (a new build) is
        // asked here. The value of kAXTrustedCheckOptionPrompt, a C global var that Swift 6 treats as shared mutable state.
        if AppState.shared.settings.onboarded { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
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
        if !AppState.shared.settings.onboarded { OnboardingWindow.shared.show() }
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
        let job = Engine.job(for: action, level: level, settings: settings, bundleID: nil)
        Task {
            let start = Date()
            do {
                let output = try await ProviderRunner.run(job, text: text, settings: settings, timeout: level.timeout,
                                                          apiKey: { _ in provider == .custom ? env["RETEXT_SMOKE_KEY"] : nil })
                try output.checkComplete()
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

    /// The tap needs the Accessibility grant; retry until it is given so no relaunch is needed. Creating the tap without
    /// the grant shows the system prompt, so it is tried only once AXIsProcessTrusted() (which never prompts) says yes:
    /// a new user sees no prompt before Onboarding's Grant Access….
    private func startHotkeys() {
        if !(AXIsProcessTrusted() && Hotkeys.start()) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startHotkeys() }
        }
    }
}

/// The menu-bar icon: SF Symbols' character.cursor.ibeam ("A" and a text cursor) with an "R" in place of the "A".
/// SF Symbols has no "R" variant, so the symbol's cursor is kept and the "R" is SF Pro's glyph scaled to the "A"'s
/// height, drawn at every scale (crisp at 1x and 2x) as a template the menu bar tints for light and dark.
@MainActor
enum MenuBarIcon {
    /// The provider-problem menu item's symbol: red, not a template, so the menu keeps its color.
    static let problem: NSImage = {
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Problem")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        return image
    }()

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
