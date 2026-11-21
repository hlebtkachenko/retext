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
}
