import AppKit
import RetextCore
import SwiftUI

/// The bar shortcut row in General: a pop-up of presets plus "Record Custom…", and a reset to ⌥Space.
struct ShortcutField: View {
    /// A preset or the custom shortcut, or "Record Custom…", which starts the recorder instead of being selected.
    private enum Choice: Hashable { case shortcut(BarShortcut), record }

    @ObservedObject private var state = AppState.shared
    @StateObject private var recorder = ShortcutRecorder()

    private var choice: Binding<Choice> {
        Binding(get: { .shortcut(state.settings.barShortcut) }, set: { picked in
            switch picked {
            case .shortcut(let shortcut): state.settings.barShortcut = shortcut
            case .record: recorder.start { state.settings.barShortcut = $0 }
            }
        })
    }

    var body: some View {
        let shortcut = state.settings.barShortcut
        IconRow(symbol: "command", tint: .indigo, title: "Shortcut",
                subtitle: recorder.recording ? "Press the new shortcut, or esc to cancel." : nil) {
            if recorder.recording {
                KeyCaps(text: recorder.live.isEmpty ? "Type Shortcut" : recorder.live, active: true)
                    .accessibilityLabel("Recording shortcut")
                Button("Cancel") { recorder.stop() }
            } else {
                Picker("Shortcut", selection: choice) {
                    ForEach(BarShortcut.presets, id: \.self) { Text($0.displayLabel).tag(Choice.shortcut($0)) }
                    if !BarShortcut.presets.contains(shortcut) { Text(shortcut.displayLabel).tag(Choice.shortcut(shortcut)) }
                    Divider()
                    Text("Record Custom…").tag(Choice.record)
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityValue(shortcut.spokenLabel)
                Button {
                    state.settings.barShortcut = RetextSettings().barShortcut
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset to \(RetextSettings().barShortcut.displayLabel)")
                .accessibilityLabel("Reset to \(RetextSettings().barShortcut.spokenLabel)")
                .disabled(shortcut == RetextSettings().barShortcut)
            }
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
}

/// A shortcut drawn as keycaps on a rounded background, like System Settings' shortcut fields.
private struct KeyCaps: View {
    let text: String
    var active = false

    var body: some View {
        Text(text)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .frame(minWidth: 110, minHeight: 24)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(active ? Color.accentColor : .clear, lineWidth: 1.5)
            }
            .foregroundStyle(active ? .secondary : .primary)
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
