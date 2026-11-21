import RetextCore
import SwiftUI

/// The bar shortcut control in General: for now a picker of the presets.
struct ShortcutField: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Picker("Open the bar with", selection: $state.settings.barShortcut) {
            ForEach(BarShortcut.presets, id: \.self) { Text($0.label).tag($0) }
        }
    }
}
