import AppKit
import RetextCore
import SwiftUI

/// The bar shortcut row in General: a field of keycaps that records a new shortcut on click, the presets in its
/// context menu, and a reset to ⌥Space.
struct ShortcutField: View {
    @ObservedObject private var state = AppState.shared
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        let shortcut = state.settings.barShortcut
        let standard = RetextSettings().barShortcut
        IconRow(symbol: "command", tint: .indigo, title: "Shortcut",
                subtitle: recorder.recording ? "Press the new shortcut, or esc to cancel." : nil) {
            Button {
                if recorder.recording { recorder.stop() } else { recorder.start { state.settings.barShortcut = $0 } }
            } label: {
                KeyCaps(caps: recorder.recording ? recorder.live.map(String.init) : Self.caps(shortcut), recording: recorder.recording)
            }
            .buttonStyle(.plain)
            .help(recorder.recording ? "Press the new shortcut, or esc to cancel." : "Click to record a new shortcut. Presets are in the context menu.")
            .accessibilityLabel(recorder.recording ? "Recording shortcut" : "Shortcut")
            .accessibilityValue(shortcut.spokenLabel)
            .accessibilityHint(recorder.recording ? "Press the new shortcut, or Escape to cancel." : "Records a new shortcut.")
            .contextMenu {
                Picker("Presets", selection: $state.settings.barShortcut) {
                    ForEach(BarShortcut.presets, id: \.self) { Text($0.displayLabel).tag($0) }
                    if !BarShortcut.presets.contains(shortcut) { Text(shortcut.displayLabel).tag(shortcut) }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Record Custom…") { recorder.start { state.settings.barShortcut = $0 } }
            }
            Button {
                state.settings.barShortcut = standard
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Reset to \(standard.displayLabel)")
            .accessibilityLabel("Reset to \(standard.spokenLabel)")
            .disabled(shortcut == standard || recorder.recording)
        }
        .onAppear {
            switch SettingsView.demoExtra {
            case "record": recorder.recording = true
            case "reject":
                recorder.recording = true
                recorder.problem = BarShortcut(keyCode: 8, modifiers: .command).problem
            default: break
            }
        }
        .onDisappear { recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in recorder.stop() }
        if let problem = recorder.problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .padding(.leading, 34)
        }
    }

    /// One keycap per modifier, in the menu order ⌃⌥⇧⌘, then the key: ⌥Space is ["⌥", "Space"].
    nonisolated static func caps(_ shortcut: BarShortcut) -> [String] {
        shortcut.modifiers.glyphs.map(String.init) + [BarShortcut.keyLabel(shortcut.keyCode)]
    }
}

/// A shortcut as keycaps in a bordered rounded field, like System Settings' shortcut fields; while recording,
/// the modifiers held so far or "Press keys…", with an accent border.
private struct KeyCaps: View {
    let caps: [String]
    let recording: Bool

    var body: some View {
        let field = RoundedRectangle(cornerRadius: 7, style: .continuous)
        HStack(spacing: 4) {
            if caps.isEmpty {
                Text("Press keys…").foregroundStyle(.secondary).padding(.horizontal, 6)
            } else {
                ForEach(caps.indices, id: \.self) { index in
                    Text(caps[index])
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 24, minHeight: 22)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
        }
        .padding(3)
        .frame(minWidth: 110, minHeight: 28)
        .background(.quaternary.opacity(0.4), in: field)
        .overlay { field.strokeBorder(recording ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator), lineWidth: recording ? 1.5 : 0.5) }
        .contentShape(field)
        .accessibilityElement(children: .ignore)
    }
}

/// Records one shortcut with a local key monitor. While recording, the event tap lets every key through
/// (`Hotkeys.paused`), so the current shortcut can be pressed and recorded too.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published var recording = false
    /// The modifiers held right now, as glyphs.
    @Published var live = ""
    /// Why the last key was rejected; recording goes on.
    @Published var problem: String?
    private var monitor: Any?
    private var accept: ((BarShortcut) -> Void)?

    func start(_ accept: @escaping (BarShortcut) -> Void) {
        stop()
        self.accept = accept
        problem = nil
        live = ""
        recording = true
        Hotkeys.paused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let (type, keyCode, flags) = (event.type, event.keyCode, event.modifierFlags)
            // Local monitors run on the main thread.
            let swallow = MainActor.assumeIsolated { self?.handle(type: type, keyCode: keyCode, flags: flags) ?? false }
            return swallow ? nil : event
        }
    }

    /// Ends recording on every exit (accept, esc, Cancel, leaving the pane or the window), so the tap never stays paused.
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        accept = nil
        if recording { Hotkeys.paused = false }
        recording = false
        live = ""
        problem = nil
    }

    /// Whether to swallow the event: every key is, so ⌘Q or ⌘W don't act while recording.
    private func handle(type: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let modifiers = Self.modifiers(flags)
        if type == .flagsChanged {
            live = modifiers.glyphs
            return false
        }
        if keyCode == 53, modifiers.isEmpty {  // esc
            stop()
            return true
        }
        let shortcut = BarShortcut(keyCode: keyCode, modifiers: modifiers)
        if let problem = shortcut.problem {
            self.problem = problem
            AccessibilityNotification.Announcement("\(shortcut.spokenLabel) can't be used. \(problem)").post()
            return true
        }
        let accept = accept
        stop()
        accept?(shortcut)
        AccessibilityNotification.Announcement("Shortcut set to \(shortcut.spokenLabel)").post()
        return true
    }

    /// Only ⌃⌥⇧⌘: caps lock, fn and the keypad flag that arrows and F-keys carry are ignored.
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> BarShortcut.Modifiers {
        let pairs: [(NSEvent.ModifierFlags, BarShortcut.Modifiers)] = [(.control, .control), (.option, .option), (.shift, .shift), (.command, .command)]
        return pairs.reduce(into: BarShortcut.Modifiers()) { if flags.contains($1.0) { $0.insert($1.1) } }
    }
}
