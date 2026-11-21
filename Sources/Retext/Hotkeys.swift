import AppKit
import Carbon.HIToolbox
import RetextCore

/// ⌥-key shortcuts via a session event tap. The tap sees keys before other apps' hotkeys
/// (another app may also register ⌥Space). The bar shortcut (`RetextSettings.barShortcut`) is always taken. ⌥1…⌥N are taken only when the frontmost app has
/// selected text, so layouts where ⌥digit types a character (Czech ⌥2 = @) keep working everywhere else.
@MainActor
enum Hotkeys {
    static var menu: (@MainActor () -> Void)?
    static var action: (@MainActor (Int) -> Void)?
    static var actionCount = 0
    /// The bar shortcut's key and modifiers (⌥Space by default).
    static var menuKey = kVK_Space
    static var menuModifiers = CGEventFlags.maskAlternate
    /// Mirrors "Improve Electron app support".
    static var electronOnSwitch = true
    /// On while a shortcut is being recorded: every key passes through to the app, none is taken.
    static var paused = false
    /// Set only while a "Copied" bubble is visible: ⌘Z then restores the previous clipboard instead of reaching the app.
    static var undo: (@MainActor () -> Void)?
    private static var tap: CFMachPort?
    private static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    /// Mirrors the settings the tap reads; called at launch and on every settings change.
    static func configure(_ settings: RetextSettings) {
        actionCount = settings.actions.count
        menuKey = Int(settings.barShortcut.keyCode)
        menuModifiers = flags(settings.barShortcut.modifiers)
        electronOnSwitch = settings.electronSupport
        if BarShortcut.characterLookup == nil {
            // The layout APIs are main-thread only; elsewhere the label falls back to the US layout.
            BarShortcut.characterLookup = { code in Thread.isMainThread ? MainActor.assumeIsolated { typedCharacter(code) } : nil }
        }
    }

    /// What a key types without modifiers in the current keyboard layout (Czech: keyCode 18 is "+"), so labels match the keycaps.
    static func typedCharacter(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, keyCode, UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        return status == noErr && length > 0 ? String(utf16CodeUnits: chars, count: length) : nil
    }

    /// The tap's modifier flags for a shortcut's modifiers.
    static func flags(_ modifiers: BarShortcut.Modifiers) -> CGEventFlags {
        let pairs: [(BarShortcut.Modifiers, CGEventFlags)] = [(.control, .maskControl), (.option, .maskAlternate), (.shift, .maskShift), (.command, .maskCommand)]
        return pairs.reduce(into: CGEventFlags()) { if modifiers.contains($1.0) { $0.insert($1.1) } }
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
        if paused { return false }
        if let undo, modifiers == .maskCommand, key == kVK_ANSI_Z {
            self.undo = nil
            DispatchQueue.main.async(execute: undo)
            return true
        }
        let fire: (@MainActor () -> Void)?
        if key == menuKey, modifiers == menuModifiers {
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
