import AppKit
import RetextCore
import SwiftUI

/// Retext is an LSUIElement app: while one of its windows (Settings, Onboarding) is open it becomes a regular app,
/// so the window gets focus and a Dock icon; it goes back to a menu-bar app when the last one closes.
@MainActor
enum AppWindows {
    /// `--demo`: windows open behind the others, with no Dock icon and no focus, so a screenshot run never takes the screen.
    static let isDemo = CommandLine.arguments.contains("--demo")

    static func bringForward(_ window: NSWindow?) {
        guard !isDemo else { window?.orderBack(nil); return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    static func closing(_ window: NSWindow) {
        let others = [SettingsWindow.shared.window, OnboardingWindow.shared.window].compactMap { $0 }
        if !others.contains(where: { $0 !== window && $0.isVisible }) { NSApp.setActivationPolicy(.accessory) }
    }
}

/// The setup walk-through: shown once on first launch (`RetextSettings.onboarded`), later from Settings → About
/// (Onboarding) and Help → Retext Onboarding.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = OnboardingWindow()
    private(set) var window: NSWindow?
    /// `--demo onboarding`: closing it doesn't mark Retext as onboarded.
    var isDemo = false
    @Published var step = Step.welcome

    enum Step: String, CaseIterable {
        case welcome, access, provider, shortcut
    }

    func show(at step: Step = .welcome) {
        self.step = step
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView()))
            w.title = "Retext Onboarding"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 560, height: 540))
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        AppWindows.bringForward(window)
    }

    func close() { window?.close() }

    func move(by offset: Int) {
        let steps = Step.allCases, i = steps.firstIndex(of: step)! + offset
        if steps.indices.contains(i) { step = steps[i] }
    }

    func windowWillClose(_ notification: Notification) {
        if !isDemo, !AppState.shared.settings.onboarded { AppState.shared.settings.onboarded = true }
        if let window { AppWindows.closing(window) }
    }
}

struct OnboardingView: View {
    @ObservedObject private var onboarding = OnboardingWindow.shared

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch onboarding.step {
                case .welcome: WelcomeStep()
                case .access: AccessStep()
                case .provider: ProviderStep()
                case .shortcut: ShortcutStep()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(minWidth: 520, minHeight: 500)
    }

    private var footer: some View {
        let steps = OnboardingWindow.Step.allCases, index = steps.firstIndex(of: onboarding.step)!
        return HStack {
            Button("Back") { onboarding.move(by: -1) }
                .opacity(index == 0 ? 0 : 1)
                .disabled(index == 0)
            Spacer()
            HStack(spacing: 7) {
                ForEach(steps.indices, id: \.self) { i in
                    Circle().fill(i == index ? Color.accentColor : Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(index + 1) of \(steps.count)")
            Spacer()
            if index == steps.count - 1 {
                Button("Done") { OnboardingWindow.shared.close() }.keyboardShortcut(.defaultAction)
            } else {
                Button(index == 0 ? "Get Started" : "Next") { onboarding.move(by: 1) }.keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

/// A step's centered header: a symbol tile (or the app icon), a title and a sentence.
private struct StepHeader<Icon: View>: View {
    let title: String
    let text: String
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(spacing: 10) {
            icon
            Text(title).font(.title.bold())
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .accessibilityElement(children: .combine)
    }
}

private struct WelcomeStep: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(title: "Welcome to Retext", text: "Fixes, rewrites or translates the text you select in any app, in place.") {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            }
            Form {
                Section {
                    IconRow(symbol: "selection.pin.in.out", tint: .blue, title: "Select text in any app")
                    IconRow(symbol: "keyboard", tint: .purple, title: "Press \(state.settings.barShortcut.displayLabel) to open the bar")
                    IconRow(symbol: "sparkles", tint: .pink, title: "Pick an action or type an instruction")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }
}

private struct AccessStep: View {
    var body: some View {
        VStack(spacing: 0) {
            StepHeader(title: "Allow Accessibility",
                       text: "Retext needs it to read and replace the text you select.") {
                SidebarTile(symbol: "accessibility", tint: .blue, size: 64)
            }
            Form {
                Section {
                    AccessibilityRow()
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
        .task {
            // Moves on only when access turns on while this step is shown, so Back from the next step stays here.
            var was = AccessibilityRow.isTrusted
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let now = AccessibilityRow.isTrusted
                if now, !was {
                    try? await Task.sleep(for: .seconds(0.8))
                    if OnboardingWindow.shared.step == .access { OnboardingWindow.shared.move(by: 1) }
                    return
                }
                was = now
            }
        }
    }
}

private struct ProviderStep: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(title: "Choose Your AI",
                       text: "Retext sends the selection to the AI you choose, with your own login or API key.") {
                SidebarTile(symbol: "sparkles", tint: .pink, size: 64)
            }
            Form {
                Section {
                    Picker("Provider", selection: $state.settings.provider) {
                        ForEach(Provider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    ProviderRow()
                    TestButton(title: "Test Provider")
                } footer: {
                    Button("Open AI Settings…") { SettingsWindow.shared.show(.ai) }.buttonStyle(.link)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }
}

private struct ShortcutStep: View {
    @ObservedObject private var state = AppState.shared
    @State private var sample = "Their going too the libary tomorow, becuase they has a exam on monday."

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(title: "Try It", text: "Pick the shortcut that opens the bar.") {
                SidebarTile(symbol: "keyboard", tint: .purple, size: 64)
            }
            Form {
                Section {
                    ShortcutField()
                }
                Section {
                    TextField("Sample text", text: $sample, axis: .vertical)
                        .labelsHidden()
                        .lineLimit(2...4)
                } footer: {
                    Text("Select the sample, press \(state.settings.barShortcut.displayLabel) and pick Fix grammar.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }
}

// MARK: Status rows (Onboarding and Settings → About)

/// Live Accessibility status, polled while visible, since macOS sends no notification when it is granted.
struct AccessibilityRow: View {
    /// `--demo`: what the row shows instead of this copy's real grant (the onboarding access demo shows "not granted").
    static var demoTrusted = true
    static var isTrusted: Bool { AppWindows.isDemo ? demoTrusted : AXIsProcessTrusted() }

    @State private var trusted = AccessibilityRow.isTrusted

    var body: some View {
        IconRow(symbol: "accessibility", tint: .blue, title: "Accessibility",
                subtitle: trusted ? nil : "Turn on Retext in Privacy & Security → Accessibility.") {
            if trusted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Grant Access…", action: Self.requestAccess)
            }
        }
        .task {
            while !Task.isCancelled {
                trusted = Self.isTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .help("Reads the selection, sees the shortcuts and pastes the result.")
    }

    /// The system prompt adds Retext to the Accessibility list (a new install is not listed before it asks); the
    /// settings pane opens next to it, where the switch is.
    static func requestAccess() {
        guard !AppWindows.isDemo else { return }
        // The value of kAXTrustedCheckOptionPrompt, a C global var that Swift 6 treats as shared mutable state.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

/// Whether the active provider is ready (Claude Code, Codex or the custom API), checked again when its settings change.
struct ProviderRow: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        // `--demo`: a fixed ready status, so a screenshot shows no real path.
        let status = AppWindows.isDemo ? ProviderStatus(ready: true, detail: Self.demoDetail(state.settings.provider), problem: nil) : state.providerStatus
        IconRow(symbol: "sparkles", tint: .pink, title: state.settings.provider.title,
                subtitle: status.flatMap { $0.ready ? nil : $0.detail }) {
            switch status {
            case nil: ProgressView().controlSize(.small)
            case let status? where status.ready:
                // The executable's path (or the API host), with ~ for the home folder so a screenshot shows no user name.
                Label((status.detail as NSString).abbreviatingWithTildeInPath, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).truncationMode(.middle).lineLimit(1)
            case .some: Label("Not ready", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .onAppear { if !AppWindows.isDemo { state.checkProvider() } }
    }

    private static func demoDetail(_ provider: Provider) -> String {
        switch provider {
        case .claude: "~/.local/bin/claude"
        case .chatgpt: "/opt/homebrew/bin/codex"
        case .custom: "openrouter.ai"
        }
    }
}
