import AppKit
import RetextCore
import ServiceManagement
import SwiftUI

/// Retext is an LSUIElement app: while this window is open it becomes a regular app so the window gets focus and a Dock icon.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private(set) var window: NSWindow?

    /// With a pane, opens on it (rebuilding the content, since the sidebar selection is view state).
    func show(_ pane: SettingsView.Pane? = nil) {
        if let pane {
            SettingsView.initialPane = pane
            if let window {
                let frame = window.frame
                window.contentViewController = NSHostingController(rootView: SettingsView())
                window.setFrame(frame, display: false)
            }
        }
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Retext Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 760, height: 620))
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case actions = "Actions", styles = "App styles", words = "Protected words", engine = "Engine", general = "General", usage = "Usage"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .actions: "list.bullet"
            case .styles: "app.badge"
            case .words: "lock"
            case .engine: "cpu"
            case .general: "gearshape"
            case .usage: "chart.bar"
            }
        }
    }

    @ObservedObject private var state = AppState.shared
    static var initialPane = Pane.actions
    @State private var pane: Pane? = SettingsView.initialPane

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.rawValue, systemImage: pane.symbol)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch pane ?? .actions {
                case .actions: ActionsPane(actions: $state.settings.actions)
                case .styles: StylesPane(styles: $state.settings.appStyles)
                case .words: WordsPane(words: $state.settings.protectedWords)
                case .engine: EnginePane(claudePath: $state.settings.claudePath,
                                         claudeFound: state.claudeFound)
                case .general: GeneralPane()
                case .usage: UsagePane(usage: state.usage, history: state.history)
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane ?? .actions).rawValue)
        }
    }
}

// MARK: Actions

private struct ActionsPane: View {
    @Binding var actions: [CustomAction]
    @State private var selection: CustomAction.ID?

    var body: some View {
        Form {
            Section {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    HStack(spacing: 8) {
                        let isSelected = selection == action.id
                        Image(systemName: action.symbol).frame(width: 20).foregroundStyle(isSelected ? Color.accentColor : .primary)
                        Text(action.title).fontWeight(isSelected ? .semibold : .regular)
                        Spacer()
                        Text(action.kind.rawValue.capitalized).foregroundStyle(.secondary)
                        Text("⌥\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = action.id }
                }
            } header: {
                Text("Action N runs with ⌥N while text is selected. Up to \(RetextSettings.maxActions).")
            } footer: {
                HStack {
                    Button("Add Action", systemImage: "plus") {
                        let action = CustomAction(title: "New action", symbol: "sparkles", prompt: "", kind: .other)
                        actions.append(action)
                        selection = action.id
                    }
                    .disabled(actions.count >= RetextSettings.maxActions)
                    Spacer()
                }
            }

            if let id = selection, actions.contains(where: { $0.id == id }) {
                ActionEditor(action: binding(id), position: actions.firstIndex { $0.id == id }!, count: actions.count,
                             move: { move(id, by: $0) },
                             delete: { actions.removeAll { $0.id == id }; selection = nil })
            }
        }
        .onAppear { selection = selection ?? actions.first?.id }
    }

    private func binding(_ id: CustomAction.ID) -> Binding<CustomAction> {
        Binding(get: { actions.first { $0.id == id } ?? CustomAction(title: "", symbol: "", prompt: "", kind: .other) },
                set: { new in if let i = actions.firstIndex(where: { $0.id == id }) { actions[i] = new } })
    }

    private func move(_ id: CustomAction.ID, by offset: Int) {
        guard let i = actions.firstIndex(where: { $0.id == id }), actions.indices.contains(i + offset) else { return }
        actions.swapAt(i, i + offset)
    }
}

private struct ActionEditor: View {
    @Binding var action: CustomAction
    let position: Int, count: Int
    let move: (Int) -> Void
    let delete: () -> Void

    var body: some View {
        Section("Edit “\(action.title)”") {
            TextField("Title", text: $action.title)
            LabeledContent("SF Symbol") {
                HStack {
                    TextField("SF Symbol", text: $action.symbol, prompt: Text("globe")).labelsHidden()
                    Image(systemName: action.symbol).frame(width: 20)
                }
            }
            Picker("Kind", selection: $action.kind) {
                Text("Grammar").tag(ActionKind.grammar)
                Text("Translate").tag(ActionKind.translate)
                Text("Other").tag(ActionKind.other)
            }
            Picker("Model", selection: $action.model) {
                Text("Auto").tag(ModelChoice.auto)
                Text("Haiku").tag(ModelChoice.haiku)
                Text("Sonnet").tag(ModelChoice.sonnet)
            }
            TextField("Prompt", text: $action.prompt, prompt: Text("What Claude should do with the selected text"), axis: .vertical)
                .lineLimit(3...8)
            HStack {
                Button("Move Up", systemImage: "arrow.up") { move(-1) }.disabled(position == 0)
                Button("Move Down", systemImage: "arrow.down") { move(1) }.disabled(position == count - 1)
                Spacer()
                Button("Delete Action", role: .destructive, action: delete)
            }
        }
    }
}

// MARK: App styles

private struct StylesPane: View {
    @Binding var styles: [AppStyle]

    var body: some View {
        Form {
            Section {
                ForEach($styles) { $style in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(appName(style.bundleID)).font(.headline)
                            Spacer()
                            Button("Remove", systemImage: "minus.circle") { styles.removeAll { $0.id == style.id } }
                                .labelStyle(.iconOnly).buttonStyle(.borderless).focusable(false)
                        }
                        HStack {
                            TextField("Bundle ID", text: $style.bundleID, prompt: Text("com.apple.mail"))
                            Menu("Running Apps") {
                                ForEach(runningApps(), id: \.0) { id, name in Button(name) { style.bundleID = id } }
                            }
                            .fixedSize()
                        }
                        TextField("Style", text: $style.style, prompt: Text("e.g. casual chat"), axis: .vertical)
                            .lineLimit(1...4)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Added to the prompt when the text is selected in that app.")
            } footer: {
                HStack {
                    Button("Add App Style", systemImage: "plus") {
                        styles.append(AppStyle(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "", style: ""))
                    }
                    Spacer()
                }
            }
        }
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID.isEmpty ? "New app" : bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func runningApps() -> [(String, String)] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let pairs = apps.compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
        return Dictionary(pairs, uniquingKeysWith: { a, _ in a }).sorted { $0.value < $1.value }.map { ($0.key, $0.value) }
    }
}

// MARK: Protected words

private struct WordsPane: View {
    @Binding var words: [String]
    @State private var newWord = ""

    var body: some View {
        Form {
            Section {
                ForEach(words, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { words.removeAll { $0 == word } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).focusable(false)
                    }
                }
                HStack {
                    TextField("New term", text: $newWord, prompt: Text("Add a term")).labelsHidden().onSubmit(add)
                    Button("Add", action: add).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Never changed or translated.")
            }
        }
    }

    private func add() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        if !words.contains(word) { words.append(word) }
        newWord = ""
    }
}

// MARK: Engine

private struct EnginePane: View {
    static let billing = "Uses your own Claude Code login: subscription usage counts against your plan's limits; API-key logins are billed to your account."
    @Binding var claudePath: String
    let claudeFound: Bool

    var body: some View {
        Form {
            Section {
                TextField("Claude Code path", text: $claudePath, prompt: Text("Found automatically"))
            } header: {
                Text("Claude Code")
            } footer: {
                Text(claudeFound ? "Leave empty to use the claude found in your login shell or the usual install paths."
                                 : "Claude Code not found. Install it, or enter the full path to the claude executable.")
                    .foregroundStyle(claudeFound ? .secondary : Color.orange)
            }
            Section {
                LabeledContent("Haiku", value: "--model \(Model.haiku) (latest Haiku)")
                LabeledContent("Sonnet", value: "--model \(Model.sonnet) (latest Sonnet)")
                LabeledContent("Runs through", value: "claude -p")
            } header: {
                Text("Models")
            } footer: {
                Text("Actions on Auto and typed instructions use Sonnet; pick Haiku per action in Actions. \(Self.billing)").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: General

private struct GeneralPane: View {
    @ObservedObject private var state = AppState.shared
    @State private var loginStatus = SMAppService.mainApp.status

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: setOpenAtLogin))
            } footer: {
                Text(loginStatusText).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show in menu bar", isOn: $state.settings.showMenuBarIcon)
            } footer: {
                Text("Off: no icon in the menu bar, so it can't hide behind the notch. Shortcuts keep working; open Retext again from Spotlight or Finder to get back to Settings.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Open the bar with", selection: $state.settings.menuShortcut) {
                    ForEach(MenuShortcut.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("Choose ⌃⌥Space if another app uses ⌥Space. macOS can also use ⌃⌥Space to switch input sources; turn that off in Keyboard Shortcuts if you pick it. Actions stay on ⌥1…⌥9.").foregroundStyle(.secondary)
            }
            Section {
                Toggle("Improve Electron app support", isOn: $state.settings.electronSupport)
            } footer: {
                Text("Asks every app you switch to for its accessibility tree, so ⌥1…⌥9 work in Electron apps (Slack, VS Code) right away. Off: Retext asks only when you use a shortcut, and the first ⌥N in such an app may pass through.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Keep history", isOn: $state.settings.keepHistory)
                LabeledContent("\(state.history.entries.count) of \(History.limit) saved") {
                    Button("Clear History", role: .destructive) { state.history = History() }
                        .disabled(state.history.entries.isEmpty)
                }
            } header: {
                Text("History")
            } footer: {
                Text("The last \(History.limit) results, with their original text, are kept in plain text in ~/Library/Application Support/Retext/history.json for Recent and the cache. Off: nothing is written and the cache isn't used.")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    /// Registers or unregisters the login item, then shows what the system reports.
    private func setOpenAtLogin(_ on: Bool) {
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        loginStatus = SMAppService.mainApp.status
    }

    private var loginStatusText: String {
        switch loginStatus {
        case .enabled: "Retext opens when you log in."
        case .requiresApproval: "Waiting for approval in System Settings → General → Login Items."
        default: "Retext doesn't open at login."
        }
    }
}

// MARK: Usage

private struct UsagePane: View {
    let usage: Usage
    let history: History

    var body: some View {
        Form {
            Section("Today") {
                let today = usage.today
                ForEach(today.callsByModel, id: \.name) { model in
                    LabeledContent("\(model.name) calls", value: "\(model.calls)")
                }
                if today.calls.isEmpty { LabeledContent("Calls", value: "0") }
                LabeledContent("Cache hits", value: "\(today.cacheHits)")
                LabeledContent("Input tokens", value: today.inputTokens.formatted())
                LabeledContent("Output tokens", value: today.outputTokens.formatted())
                LabeledContent("≈ list price", value: today.costUSD.formatted(.currency(code: "USD")))
            }
            Section {
                ForEach(usage.days.keys.sorted(by: >).prefix(14), id: \.self) { day in
                    LabeledContent(day, value: usage.days[day]!.summary.replacingOccurrences(of: "Today: ", with: ""))
                }
            } header: {
                Text("Recent days")
            } footer: {
                Text("The price is what the same tokens would cost at API list prices. \(EnginePane.billing) \(history.entries.count) results are cached.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
