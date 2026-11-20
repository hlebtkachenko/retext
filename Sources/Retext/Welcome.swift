import AppKit
import RetextCore
import SwiftUI

/// Retext is an LSUIElement app: while one of its windows (Settings, Welcome) is open it becomes a regular app,
/// so the window gets focus and a Dock icon; it goes back to a menu-bar app when the last one closes.
@MainActor
enum AppWindows {
    static func bringForward(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    static func closing(_ window: NSWindow) {
        let others = [SettingsWindow.shared.window, WelcomeWindow.shared.window].compactMap { $0 }
        if !others.contains(where: { $0 !== window && $0.isVisible }) { NSApp.setActivationPolicy(.accessory) }
    }
}

/// Shown once on first launch (`RetextSettings.onboarded`), and from the menu or Settings → General later.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindow()
    private(set) var window: NSWindow?
    /// `--demo welcome`: closing it doesn't mark Retext as onboarded.
    var isDemo = false

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: WelcomeView()))
            w.title = "Welcome to Retext"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 520, height: 560))
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        AppWindows.bringForward(window)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        if !isDemo, !AppState.shared.settings.onboarded { AppState.shared.settings.onboarded = true }
        if let window { AppWindows.closing(window) }
    }
}

struct WelcomeView: View {
    @ObservedObject private var state = AppState.shared
    @State private var sample = "Their going too the libary tomorow, becuase they has a exam on monday."

    var body: some View {
        Form {
            Section {
                Text("Select text in any app, press \(state.settings.menuShortcut.label) and pick an action or type an instruction. Retext replaces the selection with the result, in the original font.")
            }
            Section("Setup") {
                AccessibilityRow()
                ProviderRow()
            }
            Section {
                TextField("Sample text", text: $sample, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...4)
            } header: {
                Text("Try it")
            } footer: {
                Text("Select the sample text above and press \(state.settings.menuShortcut.label), then pick Fix grammar.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Open Settings…") { SettingsWindow.shared.show() }
                Spacer()
                Button("Done") { WelcomeWindow.shared.close() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }
}

// MARK: Permission rows (Welcome and Settings → General)

/// Live Accessibility status, polled while visible, since macOS sends no notification when it is granted.
struct AccessibilityRow: View {
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        LabeledContent {
            if trusted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Grant Access…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        } label: {
            Text("Accessibility")
            Text("Reads the selection, sees the shortcuts and pastes the result.")
        }
        .task {
            while !Task.isCancelled {
                trusted = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Whether the active provider is ready (Claude Code, Codex or the custom API), checked again when its settings change.
struct ProviderRow: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        let status = state.providerStatus
        LabeledContent {
            switch status {
            case nil: ProgressView().controlSize(.small)
            case let status? where status.ready:
                Label(status.detail, systemImage: "checkmark.circle.fill").foregroundStyle(.green).truncationMode(.middle).lineLimit(1)
            case .some: Label("Not ready", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        } label: {
            Text(state.settings.provider.title)
            Text(status.map { $0.ready ? readyText : $0.detail } ?? readyText)
        }
        .onAppear { state.checkProvider() }
    }

    private var readyText: String {
        state.settings.provider == .custom ? "Sends the requests to the API you set." : "Runs the requests with your own login."
    }
}
