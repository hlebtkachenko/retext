import Testing
@testable import Retext
@testable import RetextCore

/// The shortcut field draws one keycap per modifier, then one for the key.
@Suite struct ShortcutFieldTests {
    @Test func optionSpace() {
        #expect(ShortcutField.caps(.optionSpace) == ["⌥", "Space"])
    }

    @Test func modifiersInMenuOrder() {
        #expect(ShortcutField.caps(BarShortcut(keyCode: 49, modifiers: [.shift, .control])) == ["⌃", "⇧", "Space"])
        #expect(ShortcutField.caps(BarShortcut(keyCode: 96, modifiers: [.command, .option, .control, .shift])) == ["⌃", "⌥", "⇧", "⌘", "F5"])
    }
}
