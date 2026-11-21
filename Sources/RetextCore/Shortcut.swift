import Synchronization

/// Labels and validation for the bar shortcut. Key codes are the macOS virtual key codes (Carbon's kVK_*),
/// written out here so RetextCore needs no Carbon; RetextTests checks them against kVK_*.
extension BarShortcut {
    /// Keys named by a glyph or a word instead of the character they type.
    static let keyNames: [UInt16: (glyph: String, spoken: String)] = {
        var names: [UInt16: (String, String)] = [
            49: ("Space", "Space"), 36: ("↩", "Return"), 76: ("⌤", "Enter"), 48: ("⇥", "Tab"),
            51: ("⌫", "Delete"), 117: ("⌦", "Forward Delete"), 53: ("⎋", "Escape"),
            123: ("←", "Left Arrow"), 124: ("→", "Right Arrow"), 125: ("↓", "Down Arrow"), 126: ("↑", "Up Arrow"),
            115: ("↖", "Home"), 119: ("↘", "End"), 116: ("⇞", "Page Up"), 121: ("⇟", "Page Down"),
        ]
        for (number, code) in functionKeys.enumerated() { names[code] = ("F\(number + 1)", "F\(number + 1)") }
        return names
    }()

    /// F1…F20 in order.
    static let functionKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

    /// The ANSI digit keys 1…9 (not contiguous): ⌥ with one of them runs an action.
    static let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    /// What each remaining key types on the US layout; the label falls back to it when the app can't ask the
    /// current keyboard layout (`characterLookup`).
    static let ansiCharacters: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 10: "§", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
        25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 75: "Keypad /", 78: "Keypad -", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5",
        88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
    ]

    private static let lookup = Mutex<(@Sendable (UInt16) -> String?)?>(nil)

    /// What a key types in the current keyboard layout, set by the app (RetextCore can't ask the layout).
    /// nil, or a nil answer, falls back to the US layout.
    public static var characterLookup: (@Sendable (UInt16) -> String?)? {
        get { lookup.withLock { $0 } }
        set { lookup.withLock { $0 = newValue } }
    }

    /// The key alone: a glyph or name for special keys, else its character in upper case.
    public static func keyLabel(_ keyCode: UInt16) -> String {
        if let name = keyNames[keyCode] { return name.glyph }
        // Keypad keys type the same characters as the main row; the name tells them apart.
        if let ansi = ansiCharacters[keyCode], ansi.hasPrefix("Keypad") { return ansi }
        if let typed = characterLookup?(keyCode), !typed.isEmpty, typed.allSatisfy({ !$0.isWhitespace }) {
            return typed.uppercased()
        }
        return ansiCharacters[keyCode] ?? "Key \(keyCode)"
    }

    /// "⌃⌥K", "⌥Space", "⌘F5": modifiers in the macOS menu order ⌃⌥⇧⌘, then the key.
    public var displayLabel: String { modifiers.glyphs + Self.keyLabel(keyCode) }

    /// "Control Option K", for VoiceOver.
    public var spokenLabel: String {
        let words: [(Modifiers, String)] = [(.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command")]
        let key = Self.keyNames[keyCode]?.spoken ?? Self.keyLabel(keyCode)
        return (words.filter { modifiers.contains($0.0) }.map(\.1) + [key]).joined(separator: " ")
    }

    /// Why this can't be the bar shortcut, as one sentence for the recorder; nil = accepted.
    /// Matches exact modifiers, the way the event tap does: ⌥⇧1 doesn't clash with ⌥1.
    public var problem: String? {
        if !isValid {
            return "Add ⌃, ⌥ or ⌘: a key alone or with ⇧ would stop it from typing."
        }
        let key = Self.keyLabel(keyCode)
        let ansi = Self.ansiCharacters[keyCode]
        func types(_ letter: String) -> Bool { key == letter || ansi == letter }
        if modifiers == .command {
            if types("C") { return "⌘C is Copy in every app." }
            if types("V") { return "⌘V is Paste in every app." }
            if types("Z") { return "⌘Z is Undo in every app, and Retext uses it to restore the clipboard." }
        }
        if modifiers == .option, Self.digitKeys.contains(keyCode) {
            return "⌥1…⌥9 run your actions directly."
        }
        if keyCode == Self.spaceKey {
            switch modifiers {
            case .command: return "⌘Space opens Spotlight."
            case .control: return "⌃Space switches input sources."
            case [.option, .command]: return "⌥⌘Space opens a Finder search window."
            default: break
            }
        }
        return nil
    }
}

extension BarShortcut.Modifiers {
    /// "⌃⌥⇧⌘", in the macOS menu order, only the ones held.
    public var glyphs: String {
        let all: [(Self, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return all.filter { contains($0.0) }.map(\.1).joined()
    }
}
