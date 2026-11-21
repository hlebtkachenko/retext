import AppKit
import Carbon.HIToolbox
import os
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
    /// The fallback hotkey lets go meanwhile, so the recorder can also capture the current shortcut.
    static var paused = false {
        didSet { if paused { unregisterFallback() } else { registerFallback() } }
    }
    /// Set only while a "Copied" bubble is visible: ⌘Z then restores the previous clipboard instead of reaching the app.
    static var undo: (@MainActor () -> Void)?
    private static var tap: CFMachPort?
    /// Run by the Carbon fallback hotkey (set by `startFallback`); nil until then, so tests and demos never register it.
    private static var fallback: (@MainActor () -> Void)?
    private static var fallbackRef: EventHotKeyRef?
    /// The key and Carbon modifiers last tried (registered or refused), so a settings change or the launch retry tries
    /// again, and logs, only when the shortcut changed or after a shortcut is recorded.
    private static var fallbackShortcut: (key: UInt32, modifiers: UInt32)?
    private static var fallbackHandlerInstalled = false
    /// The bar shortcut's modifiers as Carbon bits (⌥ by default).
    private static var fallbackModifiers = UInt32(optionKey)
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.hapd.retext", category: "hotkeys")
    private static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    /// Mirrors the settings the tap reads; called at launch and on every settings change.
    static func configure(_ settings: RetextSettings) {
        actionCount = settings.actions.count
        menuKey = Int(settings.barShortcut.keyCode)
        menuModifiers = flags(settings.barShortcut.modifiers)
        fallbackModifiers = carbonModifiers(settings.barShortcut.modifiers)
        electronOnSwitch = settings.electronSupport
        registerFallback()
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
        unregisterFallback()
        return true
    }

    // MARK: Fallback without Accessibility

    /// Until the tap runs (it needs Accessibility), the bar shortcut would reach the front app (⌥Space types a no-break
    /// space over the selection). A Carbon hotkey, which needs no Accessibility, takes it meanwhile and runs `onPress`.
    /// Never in a demo; ends when `start()` succeeds; follows shortcut changes through `configure`.
    static func startFallback(onPress: @escaping @MainActor () -> Void) {
        guard !AppWindows.isDemo, tap == nil else { return }
        fallback = onPress
        registerFallback()
    }

    /// The Carbon modifier bits for a shortcut's modifiers.
    static func carbonModifiers(_ modifiers: BarShortcut.Modifiers) -> UInt32 {
        let pairs: [(BarShortcut.Modifiers, Int)] = [(.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey)]
        return pairs.reduce(into: UInt32(0)) { if modifiers.contains($1.0) { $0 |= UInt32($1.1) } }
    }

    /// Registers the current bar shortcut as the fallback hotkey, replacing an older one; nothing once the tap runs.
    private static func registerFallback() {
        guard fallback != nil, tap == nil, !paused, !AppWindows.isDemo else { return }
        let shortcut = (key: UInt32(menuKey), modifiers: fallbackModifiers)
        if let current = fallbackShortcut, current == shortcut { return }
        unregisterFallback()
        installFallbackHandler()
        fallbackShortcut = shortcut
        var ref: EventHotKeyRef?
        // "RTXT": Retext's signature for its one hotkey.
        let status = RegisterEventHotKey(shortcut.key, shortcut.modifiers, EventHotKeyID(signature: 0x5254_5854, id: 1),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            fallbackRef = ref
        } else {
            // Another app owns the combo: carry on without the fallback.
            log.error("RegisterEventHotKey failed for the bar shortcut: OSStatus \(status, privacy: .public)")
        }
    }

    private static func unregisterFallback() {
        if let fallbackRef { UnregisterEventHotKey(fallbackRef) }
        fallbackRef = nil
        fallbackShortcut = nil
    }

    /// One kEventHotKeyPressed handler on the application target, installed once.
    private static func installFallbackHandler() {
        guard !fallbackHandlerInstalled else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // The application event target delivers on the main thread.
            // Retext registers no other Carbon hotkey; any press it doesn't act on is passed on.
            MainActor.assumeIsolated {
                guard !Hotkeys.paused, Hotkeys.tap == nil, let fallback = Hotkeys.fallback else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async(execute: fallback)
                return noErr
            }
        }, 1, &type, nil, nil)
        if status == noErr { fallbackHandlerInstalled = true } else {
            log.error("InstallEventHandler failed for the bar shortcut: OSStatus \(status, privacy: .public)")
        }
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
