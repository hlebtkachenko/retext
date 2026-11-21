import Carbon.HIToolbox
import Testing
@testable import Retext
@testable import RetextCore

/// RetextCore writes the virtual key codes out by hand; they must match Carbon's.
@Suite struct ShortcutKeyCodesTests {
    @Test func digitKeys() {
        let carbon = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        #expect(BarShortcut.digitKeys.map(Int.init) == carbon)
    }

    @Test func functionKeys() {
        let carbon = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                      kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        #expect(BarShortcut.functionKeys.map(Int.init) == carbon)
    }

    @Test func namedKeys() {
        let carbon: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓",
            kVK_UpArrow: "↑", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        for (code, glyph) in carbon { #expect(BarShortcut.keyNames[UInt16(code)]?.glyph == glyph) }
        #expect(Int(BarShortcut.spaceKey) == kVK_Space)
    }

    @Test func copyPasteUndoKeys() {
        #expect(BarShortcut.ansiCharacters[UInt16(kVK_ANSI_C)] == "C")
        #expect(BarShortcut.ansiCharacters[UInt16(kVK_ANSI_V)] == "V")
        #expect(BarShortcut.ansiCharacters[UInt16(kVK_ANSI_Z)] == "Z")
        #expect(BarShortcut.ansiCharacters[UInt16(kVK_ANSI_K)] == "K")
    }
}
