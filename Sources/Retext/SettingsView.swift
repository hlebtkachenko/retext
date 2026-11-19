import AppKit
import RetextCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Settings; see `AppWindows` for the activation policy while it is open.
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
        AppWindows.bringForward(window)
    }

    func windowWillClose(_ notification: Notification) {
        if let window { AppWindows.closing(window) }
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
                case .words: WordsPane(settings: $state.settings)
                case .engine: EnginePane(defaultLevel: $state.settings.defaultLevel, claudePath: $state.settings.claudePath,
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
    @State private var confirmRestore = false

    var body: some View {
        Form {
            Section {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    let isSelected = selection == action.id
                    // A button, not a tap gesture, so the rows are reachable with the keyboard and VoiceOver.
                    Button { selection = action.id } label: {
                        HStack(spacing: 8) {
                            Image(systemName: action.symbol).frame(width: 20).foregroundStyle(isSelected ? Color.accentColor : .primary)
                            Text(action.title).fontWeight(isSelected ? .semibold : .regular)
                            Spacer()
                            Text(action.kind.rawValue.capitalized).foregroundStyle(.secondary)
                            Text("⌥\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Action N runs with ⌥N while text is selected, in list order: move an action up or down to change its shortcut. Up to \(RetextSettings.maxActions).")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Add Action", systemImage: "plus") {
                            let action = CustomAction(title: "New action", symbol: "sparkles", prompt: "", kind: .other)
                            actions.append(action)
                            selection = action.id
                        }
                        .disabled(actions.count >= RetextSettings.maxActions)
                        Spacer()
                        Button("Restore Default Actions…") { confirmRestore = true }
                    }
                }
            }

            if let id = selection, actions.contains(where: { $0.id == id }) {
                ActionEditor(action: binding(id), position: actions.firstIndex { $0.id == id }!, count: actions.count,
                             move: { move(id, by: $0) },
                             delete: { actions.removeAll { $0.id == id }; selection = nil })
            }
        }
        .onAppear { selection = selection ?? actions.first?.id }
        .confirmationDialog("Restore the default actions?", isPresented: $confirmRestore) {
            Button("Restore Defaults", role: .destructive) {
                actions = RetextSettings.defaultActions
                selection = actions.first?.id
            }
        } message: {
            Text("Your actions are replaced by Fix grammar, English and a translation into your Mac's language. Edited prompts and added actions are lost.")
        }
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
    @State private var confirmDelete = false

    var body: some View {
        let defaultPrompt = RetextSettings.defaultPrompt(for: action)
        Section {
            TextField("Title", text: $action.title)
            LabeledContent("SF Symbol") {
                HStack {
                    TextField("SF Symbol", text: $action.symbol, prompt: Text("globe")).labelsHidden()
                    if NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil) == nil {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).frame(width: 20)
                            .help("No SF Symbol has this name")
                            .accessibilityLabel("No SF Symbol has this name")
                    } else {
                        Image(systemName: action.symbol).frame(width: 20)
                    }
                }
            }
            Picker("Kind", selection: $action.kind) {
                Text("Grammar").tag(ActionKind.grammar)
                Text("Translate").tag(ActionKind.translate)
                Text("Other").tag(ActionKind.other)
            }
            TextField("Prompt", text: $action.prompt, prompt: Text("What Claude should do with the selected text"), axis: .vertical)
                .lineLimit(3...8)
            HStack {
                Button("Move Up", systemImage: "arrow.up") { move(-1) }.disabled(position == 0)
                Button("Move Down", systemImage: "arrow.down") { move(1) }.disabled(position == count - 1)
                Spacer()
                Button("Reset Prompt") { if let defaultPrompt { action.prompt = defaultPrompt } }
                    .disabled(defaultPrompt == nil || defaultPrompt == action.prompt)
                Button("Delete Action…", role: .destructive) { confirmDelete = true }
            }
        } header: {
            Text("Edit “\(action.title)”")
        } footer: {
            Text("Kind: Grammar and Translate keep a one-line text on one line (unless an app style applies), and a Grammar result much longer than the text is rejected as an added note. Other has no such checks. Reset Prompt puts back the built-in prompt for Grammar, or for Translate into the language named in the title.")
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Delete “\(action.title)”?", isPresented: $confirmDelete) {
            Button("Delete Action", role: .destructive, action: delete)
        } message: {
            Text("Its prompt is lost, and the actions after it move up one shortcut.")
        }
    }
}

// MARK: App styles

/// An app the style picker offers; only Sendable values, so the scan can run off the main thread.
private struct AppInfo: Hashable, Sendable {
    let bundleID: String, name: String, path: String

    /// Apps in /Applications, ~/Applications and /System/Applications (top level), one per bundle id.
    static func installed() -> [AppInfo] {
        let folders = ["/Applications", NSString(string: "~/Applications").expandingTildeInPath, "/System/Applications"]
        var seen = Set<String>()
        return folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".app") }.map { "\(folder)/\($0)" }
        }
        .compactMap { path in
            guard let id = Bundle(path: path)?.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return AppInfo(bundleID: id, name: FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""), path: path)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @MainActor static func running() -> [AppInfo] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap { app in
            guard let id = app.bundleIdentifier, let url = app.bundleURL, id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return AppInfo(bundleID: id, name: app.localizedName ?? id, path: url.path)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

@MainActor
private enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    /// The app's icon at menu size, or nil when the bundle id isn't installed.
    static func icon(path: String?) -> NSImage? {
        guard let path else { return nil }
        if let icon = cache[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        cache[path] = icon
        return icon
    }

    static func path(_ bundleID: String) -> String? {
        bundleID.isEmpty ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
    }
}

/// A menu of running apps, then the other installed ones, each with its icon.
private struct AppMenu: View {
    let title: String, systemImage: String
    let running: [AppInfo], installed: [AppInfo]
    let pick: (String) -> Void

    var body: some View {
        Menu(title, systemImage: systemImage) {
            Section("Running") { items(running) }
            Section("Installed") { items(installed.filter { app in !running.contains { $0.bundleID == app.bundleID } }) }
        }
        .fixedSize()
    }

    private func items(_ apps: [AppInfo]) -> some View {
        ForEach(apps, id: \.bundleID) { app in
            Button { pick(app.bundleID) } label: {
                Label {
                    Text(app.name)
                } icon: {
                    if let icon = AppIcons.icon(path: app.path) { Image(nsImage: icon) }
                }
            }
        }
    }
}

private struct StylesPane: View {
    @Binding var styles: [AppStyle]
    @State private var running: [AppInfo] = []
    @State private var installed: [AppInfo] = []

    var body: some View {
        Form {
            Section {
                ForEach($styles) { $style in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            let path = AppIcons.path(style.bundleID)
                            if let icon = AppIcons.icon(path: path) {
                                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "app.dashed").font(.title2).frame(width: 24, height: 24).foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading) {
                                Text(appName(style.bundleID, path: path)).font(.headline)
                                Text(style.bundleID.isEmpty ? "No app chosen" : style.bundleID)
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer()
                            AppMenu(title: "Change App", systemImage: "arrow.left.arrow.right", running: running, installed: installed) {
                                style.bundleID = $0
                            }
                            Button("Remove", systemImage: "minus.circle") { styles.removeAll { $0.id == style.id } }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                        TextField("Style", text: $style.style, prompt: Text("e.g. casual chat"), axis: .vertical)
                            .lineLimit(1...4)
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A style is added to the prompt when the text is selected in that app.").foregroundStyle(.secondary)
                    HStack {
                        AppMenu(title: "Add App Style", systemImage: "plus", running: running, installed: installed) {
                            styles.append(AppStyle(bundleID: $0, style: ""))
                        }
                        Spacer()
                    }
                }
            }
        }
        .task {
            running = AppInfo.running()
            installed = await Task.detached { AppInfo.installed() }.value
        }
    }

    private func appName(_ bundleID: String, path: String?) -> String {
        guard let path else { return bundleID.isEmpty ? "New app" : bundleID }
        return FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }
}

// MARK: Protected words

private struct WordsPane: View {
    @Binding var settings: RetextSettings
    @State private var newWord = ""
    @State private var pasting = false

    var body: some View {
        Form {
            Section {
                ForEach(settings.protectedWords, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button("Remove \(word)", systemImage: "minus.circle") { settings.protectedWords.removeAll { $0 == word } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("New term", text: $newWord, prompt: Text("Add a term, or several separated by commas")).labelsHidden().onSubmit(add)
                    Button("Add", action: add).disabled(RetextSettings.terms(in: newWord).isEmpty)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Names and terms that are never changed or translated.").foregroundStyle(.secondary)
                    HStack {
                        Button("Paste List…", systemImage: "list.bullet.clipboard") { pasting = true }
                        Spacer()
                    }
                }
            }
        }
        .sheet(isPresented: $pasting) {
            PasteListSheet { settings.addProtectedWords($0) }
        }
    }

    private func add() {
        settings.addProtectedWords(newWord)
        newWord = ""
    }
}

private struct PasteListSheet: View {
    let add: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        let count = RetextSettings.terms(in: text).count
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste a List of Terms").font(.headline)
            Text("One term per line, or separated by commas. Terms already in the list are skipped.").foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 180)
                .accessibilityLabel("Terms")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(count == 1 ? "Add 1 Term" : "Add \(count) Terms") { add(text); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(count == 0)
            }
        }
        .padding()
        .frame(width: 440)
    }
}

// MARK: Engine

private struct EnginePane: View {
    static let billing = "Uses your own Claude Code login: subscription usage counts against your plan's limits; API-key logins are billed to your account."
    @Binding var defaultLevel: Level
    @Binding var claudePath: String
    let claudeFound: Bool
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    var body: some View {
        Form {
            Section {
                TextField("Claude Code path", text: $claudePath, prompt: Text("Found automatically"))
                HStack {
                    Button("Test Claude Code", action: test).disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                    if let testResult {
                        Label(testResult.text, systemImage: testResult.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(testResult.ok ? Color.green : .orange)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("Claude Code")
            } footer: {
                Text(claudeFound ? "Leave empty to use the claude found in your login shell or the usual install paths. The test sends one tiny request at Medium."
                                 : "Claude Code not found. Install it, or enter the full path to the claude executable.")
                    .foregroundStyle(claudeFound ? .secondary : Color.orange)
            }
            Section {
                Picker("Default level", selection: $defaultLevel) {
                    ForEach(Level.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("Medium", value: "Haiku: fast, the standard prompts")
                LabeledContent("High", value: "Sonnet: deeper native rewrite of word order, word choice, missing small words and calques")
                LabeledContent("Max", value: "Opus: the most polished result, slowest")
            } header: {
                Text("Quality")
            } footer: {
                Text("⌥1…⌥9 and every bar start at the default level. In the bar, ↑ and ↓ change the level for that run. A run stops after \(Self.seconds(.medium)) seconds at Medium and High, \(Self.seconds(.max)) at Max. \(Self.billing)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func seconds(_ level: Level) -> Int64 { level.timeout.components.seconds }

    /// One tiny `claude -p` at Medium, then `claude --version`; counted in Usage like any other call.
    private func test() {
        let path = claudePath
        testing = true
        testResult = nil
        Task {
            defer { testing = false }
            let job = Job(title: "Test", model: Level.medium.model, effort: Level.medium.effort, system: "Reply with OK.")
            do {
                let output = try await ClaudeRunner().run(job, text: "ok", claudePath: path, timeout: Level.medium.timeout)
                AppState.shared.usage.recordCall(model: job.model, output: output)
                AppState.shared.claudeFound = true
                let version = await ClaudeRunner.version(claudePath: path)
                testResult = (true, version.map { "Works (Claude Code \($0))" } ?? "Works")
            } catch {
                let failure = error as? ClaudeFailure ?? .other("")
                if failure == .notFound { AppState.shared.claudeFound = false }
                testResult = (false, failure.message)
            }
        }
    }
}

// MARK: General

private struct GeneralPane: View {
    @ObservedObject private var state = AppState.shared
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var confirmClear = false
    @State private var confirmReset = false
    @State private var pendingImport: RetextSettings?
    @State private var backupError: String?

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    var body: some View {
        Form {
            Section {
                AccessibilityRow()
                ClaudeCodeRow()
                Button("Show Welcome Window…") { WelcomeWindow.shared.show() }
            } header: {
                Text("Permissions")
            }
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
                Toggle("Keep history", isOn: $state.settings.keepHistory)
                LabeledContent("\(state.history.entries.count) of \(History.limit) saved") {
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                        .disabled(state.history.entries.isEmpty)
                }
            } header: {
                Text("History")
            } footer: {
                Text("The last \(History.limit) results, with their original text, are kept in plain text in ~/Library/Application Support/Retext/history.json for Recent and the cache. Off: nothing is written and the cache isn't used.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Check for updates", isOn: $state.settings.checkForUpdates)
            } header: {
                Text("Updates")
            } footer: {
                Text("At most once a day, at launch and when the Mac wakes, Retext asks GitHub for the latest release and shows \"Update available\" in the menu when there is a newer one. Nothing is downloaded automatically. This is the only network request Retext makes itself.")
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Export Settings…", action: export)
                    Button("Import Settings…", action: chooseImport)
                    Spacer()
                    Button("Reset All Settings to Defaults…", role: .destructive) { confirmReset = true }
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Settings are saved as JSON, in the same format as settings.json. History and usage are not included and are kept on import and reset.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Improve Electron app support", isOn: $state.settings.electronSupport)
            } header: {
                Text("Advanced")
            } footer: {
                Text("Asks every app you switch to for its accessibility tree, so ⌥1…⌥9 work in Electron apps (Slack, VS Code) right away. Off: Retext asks only when you use a shortcut, and the first ⌥N in such an app may pass through.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Version", value: Self.version ?? "Development build")
                Link("Retext on GitHub", destination: URL(string: "https://github.com/hlebtkachenko/retext")!)
            } header: {
                Text("About")
            } footer: {
                Text("Not affiliated with Anthropic. Claude and Claude Code are trademarks of Anthropic.").foregroundStyle(.secondary)
            }
        }
        .onAppear { loginStatus = SMAppService.mainApp.status }
        .confirmationDialog("Clear the history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { state.history = History() }
        } message: {
            Text("Recent results and the cache are deleted.")
        }
        .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmReset) {
            Button("Reset All Settings", role: .destructive) { replaceSettings(with: RetextSettings()) }
        } message: {
            Text("Actions, app styles, protected words and every other setting go back to the defaults. Export them first to keep a copy.")
        }
        .confirmationDialog("Replace all settings with the imported ones?",
                            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Replace Settings", role: .destructive) {
                // The Claude Code path belongs to this Mac, not to the exported file.
                if var pendingImport {
                    pendingImport.claudePath = state.settings.claudePath
                    replaceSettings(with: pendingImport)
                }
                pendingImport = nil
            }
        } message: {
            Text("Your current actions, app styles, protected words and other settings are replaced.")
        }
        .alert(backupError ?? "", isPresented: Binding(get: { backupError != nil }, set: { if !$0 { backupError = nil } })) {}
    }

    /// Keeps `onboarded`, so the welcome window doesn't come back after an import or reset.
    private func replaceSettings(with new: RetextSettings) {
        var new = new
        new.onboarded = state.settings.onboarded
        state.settings = new
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Retext Settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try state.settings.encoded().write(to: url, options: .atomic) } catch {
            backupError = "Couldn't export the settings: \(error.localizedDescription)"
        }
    }

    /// Decodes first, so a file that isn't Retext settings is rejected before anything is asked or replaced.
    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { pendingImport = try RetextSettings.imported(from: Data(contentsOf: url)) } catch {
            backupError = "\(url.lastPathComponent) isn't a Retext settings file."
        }
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
                LabeledContent("≈ API list price", value: today.costUSD.formatted(.currency(code: "USD")))
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
