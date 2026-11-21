import Testing
@testable import RetextCore

@Suite(.serialized) struct ShortcutTests {
    private func shortcut(_ keyCode: UInt16, _ modifiers: BarShortcut.Modifiers) -> BarShortcut {
        BarShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    @Test func presetsAreAccepted() {
        #expect(BarShortcut.presets.allSatisfy { $0.problem == nil })
    }

    @Test func needsAModifierOtherThanShift() {
        #expect(shortcut(40, []).problem != nil)
        #expect(shortcut(40, .shift).problem != nil)
        #expect(shortcut(40, [.shift, .control]).problem == nil)
        #expect(shortcut(122, []).problem != nil)  // F1 alone
    }

    @Test func rejectsCopyPasteUndo() {
        for key: UInt16 in [8, 9, 6] { #expect(shortcut(key, .command).problem != nil) }
        // Other modifiers on the same keys don't clash: the tap and apps match exact modifiers.
        #expect(shortcut(8, [.command, .shift]).problem == nil)
        #expect(shortcut(8, [.control, .option]).problem == nil)
    }

    @Test func rejectsOptionDigitsOnly() {
        for key in BarShortcut.digitKeys { #expect(shortcut(key, .option).problem != nil) }
        #expect(shortcut(29, .option).problem == nil)  // ⌥0 runs no action
        #expect(shortcut(18, [.option, .shift]).problem == nil)
        #expect(shortcut(18, [.control, .option]).problem == nil)
    }

    @Test func rejectsSystemSpaceShortcuts() {
        #expect(shortcut(49, .command).problem != nil)
        #expect(shortcut(49, .control).problem != nil)
        #expect(shortcut(49, [.option, .command]).problem != nil)
        #expect(shortcut(49, [.control, .command]).problem == nil)
    }

    @Test func labels() {
        #expect(BarShortcut.optionSpace.displayLabel == "⌥Space")
        #expect(BarShortcut.controlShiftSpace.displayLabel == "⌃⇧Space")
        #expect(shortcut(40, [.command, .control, .shift, .option]).displayLabel == "⌃⌥⇧⌘K")
        #expect(shortcut(36, .command).displayLabel == "⌘↩")
        #expect(shortcut(48, .control).displayLabel == "⌃⇥")
        #expect(shortcut(126, .option).displayLabel == "⌥↑")
        #expect(shortcut(51, .option).displayLabel == "⌥⌫")
        #expect(shortcut(96, .control).displayLabel == "⌃F5")
        #expect(shortcut(90, .control).displayLabel == "⌃F20")
        #expect(shortcut(200, .control).displayLabel == "⌃Key 200")
    }

    @Test func spokenLabels() {
        #expect(BarShortcut.controlOptionSpace.spokenLabel == "Control Option Space")
        #expect(shortcut(126, [.shift, .command]).spokenLabel == "Shift Command Up Arrow")
        #expect(shortcut(40, .option).spokenLabel == "Option K")
    }

    /// The app's layout lookup wins for character keys; glyph keys keep their glyph.
    @Test func layoutCharacterWins() {
        let saved = BarShortcut.characterLookup
        defer { BarShortcut.characterLookup = saved }
        BarShortcut.characterLookup = { $0 == 6 ? "y" : nil }  // German: the Z key types Y
        #expect(shortcut(6, .option).displayLabel == "⌥Y")
        #expect(shortcut(49, .option).displayLabel == "⌥Space")
        #expect(shortcut(40, .option).displayLabel == "⌥K")  // nil answer: US layout
        BarShortcut.characterLookup = { _ in "1" }
        #expect(shortcut(83, .control).displayLabel == "⌃Keypad 1")
    }
}
