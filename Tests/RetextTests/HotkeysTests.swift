import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import Retext
import RetextCore

@MainActor
@Suite struct HotkeysTests {
    /// The two 1.x presets give the tap the same key and flags as before.
    @Test func oldPresetsKeepTheirKeyAndFlags() {
        var settings = RetextSettings()
        settings.barShortcut = .optionSpace
        Hotkeys.configure(settings)
        #expect(Hotkeys.menuKey == kVK_Space && Hotkeys.menuModifiers == .maskAlternate)
        settings.barShortcut = .controlOptionSpace
        Hotkeys.configure(settings)
        #expect(Hotkeys.menuKey == kVK_Space && Hotkeys.menuModifiers == [.maskControl, .maskAlternate])
        #expect(Hotkeys.flags([.control, .shift, .command]) == [.maskControl, .maskShift, .maskCommand])
        Hotkeys.configure(RetextSettings())
    }

    /// The Carbon fallback hotkey gets the same modifiers as Carbon's own constants.
    @Test func carbonModifiersMatchCarbonBits() {
        #expect(Hotkeys.carbonModifiers(.option) == UInt32(optionKey))
        #expect(Hotkeys.carbonModifiers([.control, .option]) == UInt32(controlKey | optionKey))
        #expect(Hotkeys.carbonModifiers([.command, .shift]) == UInt32(cmdKey | shiftKey))
        #expect(Hotkeys.carbonModifiers([.control, .option, .shift, .command]) == UInt32(cmdKey | optionKey | controlKey | shiftKey))
        #expect(Hotkeys.carbonModifiers([]) == 0)
    }
}
