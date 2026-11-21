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

    /// With a pane, opens on it (rebuilding the content, since the sidebar selection is view state). The title is set
    /// here, before SwiftUI's first update: navigationTitle renames the window when another pane is picked, but leaves
    /// "Untitled" when it opens on a pane other than Overview, and a title set from the view resets the pane's state.
    func show(_ pane: SettingsView.Pane? = nil) {
        if let pane {
            SettingsView.initialPane = pane
            if let window {
                let frame = window.frame
                window.contentViewController = NSHostingController(rootView: SettingsView())
                window.setFrame(frame, display: false)
                window.title = pane.rawValue
            }
        }
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = SettingsView.initialPane.rawValue
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
        case overview = "Overview", actions = "Actions", styles = "App styles", words = "Protected words", engine = "Engine", general = "General", usage = "Usage"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .overview: "info.circle"
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
    static var initialPane = Pane.overview
    /// `--demo settings <pane> <extra>`: the word after the pane opens a dialog or expands a row, for screenshots.
    static let demoExtra: String? = CommandLine.arguments.firstIndex(of: "--demo").flatMap { i in
        CommandLine.arguments.dropFirst(i + 1).first == "settings" ? CommandLine.arguments.dropFirst(i + 3).first : nil
    }
    @State private var pane: Pane? = SettingsView.initialPane

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.rawValue, systemImage: pane.symbol)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch pane ?? .overview {
                case .overview: OverviewPane()
                case .actions: ActionsPane(actions: $state.settings.actions)
                case .styles: StylesPane(styles: $state.settings.appStyles)
                case .words: WordsPane(settings: $state.settings)
                case .engine: EnginePane()
                case .general: GeneralPane()
                case .usage: UsagePane(usage: state.usage)
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane ?? .overview).rawValue)
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
                    // Multi-line, so a pasted list keeps its lines; Return adds every term.
                    TextField("New term", text: $newWord, prompt: Text("Add terms, one per line or separated by commas"), axis: .vertical)
                        .lineLimit(1...6).labelsHidden().onSubmit(add)
                    Button("Add", action: add).disabled(RetextSettings.terms(in: newWord).isEmpty)
                }
            } footer: {
                Text("Names and terms that are never changed or translated.").foregroundStyle(.secondary)
            }
        }
    }

    private func add() {
        settings.addProtectedWords(newWord)
        newWord = ""
    }
}

// MARK: Engine

private struct EnginePane: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        let provider = state.settings.provider
        Form {
            Section {
                Picker("Provider", selection: $state.settings.provider) {
                    ForEach(Provider.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                Text(Self.about(provider)).foregroundStyle(.secondary)
            }
            switch provider {
            case .claude: ClaudeSection(claudePath: $state.settings.claudePath)
            case .chatgpt: ChatGPTSection(settings: $state.settings)
            case .custom: CustomAPISection(custom: $state.settings.custom)
            }
            Section {
                Picker("Default level", selection: $state.settings.defaultLevel) {
                    ForEach(Level.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                // Name with its description below, the same layout for every level whatever the description's length.
                ForEach(Level.allCases, id: \.self) { level in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.title)
                        Text(describe(level)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Quality")
            } footer: {
                Text("In the bar, ↑ and ↓ change the level for one run; a run stops after \(Self.seconds(.medium)) s, \(Self.seconds(.max)) s at Max.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func about(_ provider: Provider) -> String {
        switch provider {
        case .claude: "Uses your own Claude Code login: subscription usage counts against your plan's limits; API-key logins are billed to your account."
        case .chatgpt: "Uses your own ChatGPT login through the Codex CLI, without Retext reading or storing your OpenAI credentials: your text goes to OpenAI and usage counts against your plan's Codex limits."
        case .custom: "Sends the selected text to the API at the base URL you set, whose pricing and privacy terms apply."
        }
    }

    private func describe(_ level: Level) -> String {
        let role = switch level {
        case .medium: "fast, the standard prompts"
        case .high: "deeper native rewrite of word order, word choice, missing small words and calques"
        case .max: "the most polished result, slowest"
        }
        let m = state.settings.model(for: level)
        switch state.settings.provider {
        case .claude: return "\(Model.shortName(m.model)): \(role)"
        case .chatgpt, .custom:
            guard !m.model.isEmpty else { return "No model set" }
            return "\(m.model)\(m.effort.isEmpty ? "" : " (\(m.effort))"): \(role)"
        }
    }

    static func seconds(_ level: Level) -> Int64 { level.timeout.components.seconds }
}

/// Runs one tiny request at Medium with the active provider; counted in Usage like any other call.
private struct TestButton: View {
    let title: String
    /// Extra checks before the request (nil = go on) and a description of what was tested after it.
    var precheck: () async -> ClaudeFailure? = { nil }
    var success: () async -> String = { "Works" }
    @ObservedObject private var state = AppState.shared
    @State private var testing = false
    @State private var result: (ok: Bool, text: String)?

    var body: some View {
        HStack {
            Button(title, action: test).disabled(testing)
            if testing { ProgressView().controlSize(.small) }
            if let result {
                Label(result.text, systemImage: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(result.ok ? Color.green : .orange)
                    .textSelection(.enabled)
            }
        }
    }

    private func test() {
        let settings = state.settings
        testing = true
        result = nil
        Task {
            defer { testing = false }
            let m = settings.model(for: .medium)
            let job = Job(title: "Test", provider: settings.provider, model: m.model, effort: m.effort, system: "Reply with OK.")
            do {
                if let failure = await precheck() { throw failure }
                let output = try await ProviderRunner.run(job, text: "ok", settings: settings, timeout: Level.medium.timeout)
                state.usage.recordCall(model: job.model, output: output)
                result = (true, await success())
            } catch {
                let failure = error as? ClaudeFailure ?? .other("")
                result = (false, failure.message(for: settings.provider))
            }
            state.checkProvider()
        }
    }
}

private struct ClaudeSection: View {
    @Binding var claudePath: String
    @ObservedObject private var state = AppState.shared

    var body: some View {
        let found = state.providerStatus?.ready != false
        Section {
            TextField("Claude Code path", text: $claudePath, prompt: Text("Found automatically"))
            TestButton(title: "Test Claude Code", success: {
                await ClaudeRunner.version(claudePath: claudePath).map { "Works (Claude Code \($0))" } ?? "Works"
            })
        } header: {
            Text("Claude Code")
        } footer: {
            Text(found ? "The test sends one tiny request at Medium."
                       : "Claude Code not found: install it, or enter the full path to the claude executable.")
                .foregroundStyle(found ? .secondary : Color.orange)
        }
    }
}

private struct ChatGPTSection: View {
    static let efforts = ["low", "medium", "high", "xhigh", "max"]
    @Binding var settings: RetextSettings
    /// nil while checking; then the login state, or nil again when Codex can't be run.
    @State private var loggedIn: Bool??
    @State private var models: [String] = []

    var body: some View {
        Section {
            TextField("Codex path", text: $settings.codexPath, prompt: Text("Found automatically"))
            LabeledContent("Login") {
                switch loggedIn {
                case nil: ProgressView().controlSize(.small)
                case .some(true): Label("Signed in with ChatGPT", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .some(false): Label("Not signed in with ChatGPT", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .some(nil): Label("Codex not found", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            TestButton(title: "Test ChatGPT", precheck: {
                switch await CodexRunner.isLoggedInWithChatGPT(codexPath: settings.codexPath) {
                case nil: .notFound
                case false?: .notLoggedIn
                case true?: nil
                }
            }, success: {
                await CodexRunner.version(codexPath: settings.codexPath).map { "Works (Codex \($0))" } ?? "Works"
            })
        } header: {
            Text("ChatGPT (Codex)")
        } footer: {
            Text("Needs the Codex CLI (npm install -g @openai/codex) signed in with codex login using your ChatGPT account; Retext runs it with its tools, web search, plugins and your Codex settings turned off.")
                .foregroundStyle(.secondary)
        }
        .task(id: settings.codexPath) {
            loggedIn = nil
            loggedIn = .some(await CodexRunner.isLoggedInWithChatGPT(codexPath: settings.codexPath))
            models = await CodexRunner.models(codexPath: settings.codexPath)
        }
        Section {
            ForEach(Level.allCases, id: \.self) { level in
                let base = Provider.chatgpt.defaultModel(level)
                LabeledContent(level.title) {
                    HStack {
                        Picker("Model", selection: field(level, \.model)) {
                            Text("Default (\(base.model))").tag("")
                            ForEach(options(level), id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Effort", selection: field(level, \.effort)) {
                            Text("Default (\(base.effort))").tag("")
                            ForEach(Self.efforts, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        } header: {
            Text("ChatGPT models")
        } footer: {
            Text("If a run says the model isn't available, pick another model or effort for that level; the list comes from codex debug models.")
                .foregroundStyle(.secondary)
        }
    }

    /// Listed models plus the saved one, so a model that left the list still shows.
    private func options(_ level: Level) -> [String] {
        let saved = settings.chatGPTModels[level]?.model ?? ""
        return models + (saved.isEmpty || models.contains(saved) ? [] : [saved])
    }

    private func field(_ level: Level, _ path: WritableKeyPath<ProviderModel, String>) -> Binding<String> {
        Binding(get: { settings.chatGPTModels[level]?[keyPath: path] ?? "" },
                set: { settings.chatGPTModels[level, default: ProviderModel()][keyPath: path] = $0 })
    }
}

private struct CustomAPISection: View {
    @Binding var custom: CustomProviderSettings
    @ObservedObject private var state = AppState.shared
    @State private var key = ""
    @State private var keyError = false
    @State private var confirmRemove = false
    /// Bumped on save and remove, so the view reads the Keychain again.
    @State private var keyVersion = 0

    var body: some View {
        Section {
            LabeledContent("Base URL") {
                HStack {
                    TextField("Base URL", text: $custom.baseURL, prompt: Text("https://openrouter.ai/api/v1")).labelsHidden()
                    Menu("Presets") {
                        ForEach(CustomProviderSettings.presets, id: \.url) { preset in
                            Button("\(preset.name): \(preset.url)") { custom.baseURL = preset.url }
                        }
                    }
                    .fixedSize()
                }
            }
            LabeledContent("API key") {
                HStack {
                    SecureField("API key", text: $key, prompt: Text(keyPrompt)).labelsHidden()
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey).disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || custom.keyAccount == nil)
                    if keySaved, let account = custom.keyAccount {
                        Button("Remove…", role: .destructive) { confirmRemove = true }
                            .foregroundStyle(.red)
                            .confirmationDialog("Remove the API key?", isPresented: $confirmRemove) {
                                Button("Remove Key", role: .destructive) {
                                    Keychain.setAPIKey("", account: account)
                                    keyVersion += 1
                                    state.checkProvider()
                                }
                                Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
                            } message: {
                                Text("The key saved for \(custom.endpoint?.host ?? "this server") is deleted from the Keychain.")
                            }
                    }
                }
            }
            TestButton(title: "Test API", success: { "Works (\(custom.endpoint?.host ?? "API"))" })
        } header: {
            Text("Custom API")
        } footer: {
            Text(keyError ? "The Keychain didn't accept the key. Try again."
                          : "Any OpenAI-compatible Chat Completions API (http only on the local network); the key is kept in the macOS Keychain and sent only to this URL's server.")
                .foregroundStyle(keyError ? Color.orange : .secondary)
        }
        Section {
            ForEach(Level.allCases, id: \.self) { level in
                LabeledContent(level.title) {
                    HStack {
                        TextField("Model", text: field(level, \.model), prompt: Text("Model id"))
                        TextField("Effort", text: field(level, \.effort), prompt: Text("Effort (optional)")).frame(width: 130)
                    }
                    .labelsHidden()
                }
            }
        } header: {
            Text("Models")
        } footer: {
            Text("The model id the API expects for each level; effort is sent as reasoning_effort only when set.")
                .foregroundStyle(.secondary)
        }
    }

    /// Read from the Keychain on each render (attributes only), so it follows the base URL's host as it changes.
    private var keySaved: Bool { _ = keyVersion; return Keychain.hasAPIKey(account: custom.keyAccount) }

    private var keyPrompt: String {
        guard let host = custom.endpoint?.host else { return "Enter the base URL first" }
        return keySaved ? "Saved for \(host)" : "No key saved for this host"
    }

    private func saveKey() {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty, let account = custom.keyAccount else { return }
        keyError = !Keychain.setAPIKey(key, account: account)
        key = ""
        keyVersion += 1
        state.checkProvider()
    }

    private func field(_ level: Level, _ path: WritableKeyPath<ProviderModel, String>) -> Binding<String> {
        Binding(get: { custom.models[level]?[keyPath: path] ?? "" },
                set: { custom.models[level, default: ProviderModel()][keyPath: path] = $0 })
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

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: { setOpenAtLogin($0) }))
            } footer: {
                if loginStatus == .requiresApproval {
                    Text("Waiting for approval in System Settings → General → Login Items.").foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Show in menu bar", isOn: $state.settings.showMenuBarIcon)
            } footer: {
                Text("Off: shortcuts keep working; open Retext again from Spotlight or Finder to get back to Settings.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Open the bar with", selection: $state.settings.menuShortcut) {
                    ForEach(MenuShortcut.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("Choose ⌃⌥Space if another app uses ⌥Space; macOS may use ⌃⌥Space to switch input sources, which you can turn off in Keyboard Shortcuts.").foregroundStyle(.secondary)
            }
            Section {
                Toggle("Preview before replacing", isOn: $state.settings.previewBeforeReplace)
            } footer: {
                Text("Text that can't be edited is copied either way.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Keep history", isOn: $state.settings.keepHistory)
                LabeledContent("\(state.history.entries.count) of \(History.limit) saved") {
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                        .foregroundStyle(.red)
                        .disabled(state.history.entries.isEmpty)
                }
            } header: {
                Text("History")
            } footer: {
                Text("The last \(History.limit) results and the first \(HistoryEntry.inputLimit) characters of each selection are kept in plain text in ~/Library/Application Support/Retext/history.json for Recent and the cache.")
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Export Settings…", action: export)
                    Button("Import Settings…", action: chooseImport)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("History and usage are not included and are kept on import and reset.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Improve Electron app support", isOn: $state.settings.electronSupport)
            } header: {
                Text("Advanced")
            } footer: {
                Text("Asks every app you switch to for its accessibility tree, so ⌥1…⌥9 work in Electron apps (Slack, VS Code) right away.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Reset All Settings to Defaults…", role: .destructive) { confirmReset = true }
                    .foregroundStyle(.red)
                    // Here, not on the Form, so only this dialog is critical.
                    .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmReset) {
                        Button("Reset All Settings", role: .destructive) { replaceSettings(with: RetextSettings()) }
                        // Cancel is the default button, so Return never resets.
                        Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
                    } message: {
                        Text("Actions, app styles, protected words, the provider and every other setting go back to the defaults. History and usage are kept. Export your settings first to keep a copy.")
                    }
                    .dialogSeverity(.critical)
            }
        }
        .onAppear {
            loginStatus = SMAppService.mainApp.status
            if SettingsView.demoExtra == "reset" { confirmReset = true }
        }
        .confirmationDialog("Clear the history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { state.history = History() }
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: {
            Text("Recent results and the cache are deleted.")
        }
        .confirmationDialog("Replace all settings with the imported ones?",
                            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Replace Settings", role: .destructive) {
                // The Claude Code and Codex paths belong to this Mac, not to the exported file.
                if var pendingImport {
                    pendingImport.claudePath = state.settings.claudePath
                    pendingImport.codexPath = state.settings.codexPath
                    // The API key is saved for the current server: an imported file must not point it at another server.
                    pendingImport.custom.baseURL = state.settings.custom.baseURL
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
}

// MARK: Usage

private struct UsagePane: View {
    let usage: Usage

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
                LabeledContent("Price", value: Self.price(today))
            }
            Section {
                ForEach(usage.days.keys.sorted(by: >).prefix(14), id: \.self) { day in
                    LabeledContent(day, value: Self.summary(usage.days[day]!))
                }
            } header: {
                Text("Recent days")
            } footer: {
                Text("The price is the Claude Code list price for the same tokens; ChatGPT and custom API calls count tokens only.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One formatter for every amount, so all rows show the Mac's currency format.
    private static func price(_ day: UsageDay) -> String { day.costUSD.formatted(.currency(code: "USD")) }

    private static func summary(_ day: UsageDay) -> String {
        let calls = day.callsByModel.map { "\($0.name) \($0.calls)" }.joined(separator: ", ")
        return [calls.isEmpty ? "0 calls" : calls, "\(day.cacheHits) cached",
                "\((day.inputTokens + day.outputTokens).formatted()) tokens", price(day)].joined(separator: ", ")
    }
}
