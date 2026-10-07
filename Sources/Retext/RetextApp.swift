import Carbon.HIToolbox
import RetextCore
import SwiftUI

@main
struct RetextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("Retext", systemImage: "character.cursor.ibeam", isInserted: showIcon) {
            // Clicking an action runs it on the selection in the app in front, like its ⌥N shortcut.
            ForEach(Array(state.settings.actions.enumerated()), id: \.element.id) { index, action in
                Button { delegate.controller.trigger(index) } label: { Label(action.title, systemImage: action.symbol) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .option)
            }
            Divider()
            Menu("Recent (click to copy)") {
                if state.history.entries.isEmpty { Text("Nothing yet") }
                ForEach(state.history.entries) { entry in
                    Button(Self.short(entry)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.output, forType: .string)
                    }
                }
            }
            Button(state.usage.today.summary) { SettingsWindow.shared.show(.usage) }
            Divider()
            // Shown only when something blocks Retext; each opens the place that fixes it.
            if !delegate.hotkeyOK {
                Button("Allow Accessibility…", systemImage: "exclamationmark.triangle") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            if !state.claudeFound {
                Button("Claude Code not found…", systemImage: "exclamationmark.triangle") { SettingsWindow.shared.show(.engine) }
            }
            Button("Settings…") { SettingsWindow.shared.show() }.keyboardShortcut(",")
            Button("Quit Retext") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
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
        if let i = CommandLine.arguments.firstIndex(of: "--demo") {
            let state = CommandLine.arguments.dropFirst(i + 1).first ?? "menu"
            if state == "settings" {
                let pane = CommandLine.arguments.dropFirst(i + 2).first ?? ""
                SettingsView.initialPane = SettingsView.Pane.allCases.first { $0.rawValue.lowercased().hasPrefix(pane) } ?? .actions
                SettingsWindow.shared.show()
                print("window \(SettingsWindow.shared.window?.windowNumber ?? 0)")  // for screencapture -l
                fflush(stdout)
                return
            }
            controller.demo(state)
            return
        }
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        Hotkeys.menu = { [weak self] in self?.controller.trigger() }
        Hotkeys.action = { [weak self] index in self?.controller.trigger(index) }
        Hotkeys.configure(AppState.shared.settings)
        AppState.shared.checkClaude()
        startHotkeys()
        // Electron apps expose their selection only after AXManualAccessibility is set. With "Improve Electron app
        // support" on, set it on every app switch so the ⌥N selection check in the event tap works there before the
        // first ⌥Space; with it off, the tap and SelectionIO.read() set it only when they read.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            if Hotkeys.electronOnSwitch, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                SelectionIO.enableElectronAccessibility(app)
            }
        }
        if Hotkeys.electronOnSwitch, let app = NSWorkspace.shared.frontmostApplication { SelectionIO.enableElectronAccessibility(app) }
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
enum Hotkeys {
    static var menu: (() -> Void)?
    static var action: ((Int) -> Void)?
    static var actionCount = 0
    /// ⌥ or ⌃⌥, with Space, opens the bar.
    static var menuModifiers = CGEventFlags.maskAlternate
    /// Mirrors "Improve Electron app support".
    static var electronOnSwitch = true
    /// Set only while a "Copied" bubble is visible: ⌘Z then restores the previous clipboard instead of reaching the app.
    static var undo: (() -> Void)?
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
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = Hotkeys.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let modifiers = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if let undo = Hotkeys.undo, modifiers == .maskCommand, key == kVK_ANSI_Z {
                Hotkeys.undo = nil
                DispatchQueue.main.async(execute: undo)
                return nil
            }
            let fire: (() -> Void)?
            if key == kVK_Space, modifiers == Hotkeys.menuModifiers {
                fire = Hotkeys.menu
            } else if modifiers == .maskAlternate, let index = Hotkeys.digits.firstIndex(of: key), index < Hotkeys.actionCount,
                      Hotkeys.frontmostHasSelection() {
                fire = Hotkeys.action.map { action in { action(index) } }
            } else {
                fire = nil
            }
            guard let fire else { return Unmanaged.passUnretained(event) }
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { DispatchQueue.main.async(execute: fire) }
            return nil
        }, userInfo: nil) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        return true
    }

    /// Non-empty AXSelectedText in the frontmost app's focused element. Short AX timeouts keep the tap from stalling.
    private static func frontmostHasSelection() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return false }
        if !electronOnSwitch { SelectionIO.enableElectronAccessibility(app) }
        guard let element = SelectionIO.focusedElement(of: app, timeout: 0.1) else { return false }
        return !(SelectionIO.selectedText(element) ?? "").isEmpty
    }
}
