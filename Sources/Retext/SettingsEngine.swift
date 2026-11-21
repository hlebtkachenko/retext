import AppKit
import RetextCore
import SwiftUI

// MARK: AI

struct EnginePane: View {
    @ObservedObject private var state = AppState.shared
    /// The models `codex debug models` lists, for the ChatGPT model pickers.
    @State private var codexModels: [String] = []
    /// ChatGPT: nil while checking; then the login state, or nil again when Codex can't be run.
    @State private var loggedIn: Bool??
    /// Custom API: the Keychain didn't accept the last key.
    @State private var keyError = false

    var body: some View {
        let provider = state.settings.provider
        Form {
            PageDescription(.ai)
            Section {
                IconRow(symbol: "cpu", tint: .indigo, title: "Provider", subtitle: Self.about(provider)) {
                    PopUpPicker("Provider", selection: $state.settings.provider, options: Provider.allCases) { $0.title }
                        .fixedSize()
                }
                switch provider {
                case .claude: ClaudeSection(claudePath: $state.settings.claudePath)
                case .chatgpt: ChatGPTSection(settings: $state.settings, loggedIn: loggedIn)
                case .custom: CustomAPISection(custom: $state.settings.custom, keyError: $keyError)
                }
            } header: {
                SectionTitle("Provider")
            } footer: {
                footer(provider)
            }
            Section {
                // No icon and no section title: one plain row, the picker on the title's line.
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Default Effort")
                        Text("Change it for one run with ↑ and ↓ in the bar.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Picker("Default Effort", selection: $state.settings.defaultLevel) {
                        ForEach(Level.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            Section {
                switch provider {
                case .claude:
                    ForEach(Level.allCases, id: \.self) { level in
                        ModelRow(provider: .claude, level: level, models: $state.settings.claudeModels,
                                 listed: ClaudeModels.aliases, efforts: ClaudeModels.efforts)
                    }
                case .chatgpt:
                    ForEach(Level.allCases, id: \.self) { level in
                        ModelRow(provider: .chatgpt, level: level, models: $state.settings.chatGPTModels,
                                 listed: codexModels, efforts: ChatGPTModels.efforts)
                    }
                case .custom: CustomModelsSection(custom: $state.settings.custom)
                }
            } header: {
                SectionTitle("Models")
            }
        }
        .onAppear {
            // `--demo settings ai chatgpt|custom` shows another provider's rows; demo settings are never saved.
            if let demo = SettingsView.demoExtra.flatMap(Provider.init(rawValue:)) { state.settings.provider = demo }
        }
        .task(id: provider == .chatgpt ? state.settings.codexPath : nil) {
            guard provider == .chatgpt else { return }
            let path = state.settings.codexPath
            loggedIn = nil
            async let login = CodexRunner.isLoggedInWithChatGPT(codexPath: path)
            async let models = CodexRunner.models(codexPath: path)
            loggedIn = .some(await login)
            codexModels = await models
        }
    }

    /// One footer for the Provider section, about the chosen provider's setup.
    @ViewBuilder private func footer(_ provider: Provider) -> some View {
        switch provider {
        case .claude:
            if state.providerStatus?.ready == false {
                Text("Claude Code not found: install it, or enter the full path to the claude executable.").foregroundStyle(.orange)
            }
        case .chatgpt:
            if loggedIn != .some(true) {
                Text("Install with npm install -g @openai/codex, then sign in with codex login.").foregroundStyle(.secondary)
            }
        case .custom:
            Text(keyError ? "The Keychain didn't accept the key. Try again."
                          : "Any OpenAI-compatible API (http only on your local network). The key stays in the Keychain and is sent only to this server.")
                .foregroundStyle(keyError ? Color.orange : .secondary)
        }
    }

    static func about(_ provider: Provider) -> String {
        switch provider {
        case .claude: "Uses your Claude Code login; plan limits apply, API keys are billed."
        case .chatgpt: "Uses your ChatGPT login through Codex; your plan's Codex limits apply."
        case .custom: "Sends your text to the API below; its pricing and privacy terms apply."
        }
    }

    static func seconds(_ level: Level) -> Int64 { level.timeout.components.seconds }
}

/// The Claude Code rows of the Provider section.
private struct ClaudeSection: View {
    @Binding var claudePath: String

    var body: some View {
        TextField("Claude Code Path", text: $claudePath, prompt: Text("Found automatically"))
        TestButton(title: "Test Claude Code", success: {
            await ClaudeRunner.version(claudePath: claudePath).map { "Works (Claude Code \($0))" } ?? "Works"
        })
    }
}

/// The ChatGPT rows of the Provider section; EnginePane checks the login, so the footer can follow it too.
private struct ChatGPTSection: View {
    @Binding var settings: RetextSettings
    /// nil while checking; then the login state, or nil again when Codex can't be run.
    let loggedIn: Bool??

    var body: some View {
        TextField("Codex Path", text: $settings.codexPath, prompt: Text("Found automatically"))
        LabeledContent("Login") {
            switch loggedIn {
            case nil: ProgressView().controlSize(.small)
            case .some(true): Label("Signed in with ChatGPT", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .some(false): Label("Not signed in with ChatGPT", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .some(nil): Label("Codex not found", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .help("Retext never reads or stores your OpenAI credentials, and runs Codex with its tools, web search, plugins and your Codex settings turned off.")
        TestButton(title: "Test ChatGPT", precheck: {
            switch await CodexRunner.isLoggedInWithChatGPT(codexPath: settings.codexPath) {
            case nil: .notFound
            case false?: .notLoggedIn
            case true?: nil
            }
        }, success: {
            await CodexRunner.version(codexPath: settings.codexPath).map { "Works (Codex \($0))" } ?? "Works"
        })
    }
}

/// The Models choices for Claude Code: the `claude --model` aliases and the `claude --effort` values.
private enum ClaudeModels {
    static let aliases = ["haiku", "sonnet", "opus", "fable"]
    static let efforts = ["low", "medium", "high", "xhigh", "max"]
}

/// The Models choices for ChatGPT; its models come from `codex debug models`.
private enum ChatGPTModels {
    static let efforts = ["low", "medium", "high", "xhigh", "max"]
}

/// The Models rows' columns, the same on every provider: a title column as wide as the longest level title, the model
/// control filling the rest, and a fixed effort column, so the controls line up on every row at any window width.
private enum ModelColumns {
    @MainActor static let title: CGFloat = Level.allCases
        .map { ($0.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width }
        .max()!.rounded(.up) + 2
    static let effort: CGFloat = 150
}

/// One level's Models row for a provider with built-in models (Claude Code, ChatGPT): a model and an effort pop-up,
/// each with "Default (<built-in>)" first; the time limit is in the tooltip.
private struct ModelRow: View {
    let provider: Provider
    let level: Level
    @Binding var models: [Level: ProviderModel]
    /// The models to offer; the saved one is added when it isn't listed, so a model that left the list still shows.
    let listed: [String]
    let efforts: [String]

    var body: some View {
        let base = provider.defaultModel(level)
        IconRow(symbol: symbol(level).name, tint: symbol(level).tint, title: level.title, titleWidth: ModelColumns.title) {
            // "" is the provider's default for the level.
            PopUpPicker("\(level.title) Model", selection: field(\.model), options: [""] + options(listed, saved: \.model),
                        width: .fill) {
                $0.isEmpty ? "Default (\(base.model))" : $0
            }
            PopUpPicker("\(level.title) Effort", selection: field(\.effort), options: [""] + options(efforts, saved: \.effort),
                        width: .fixed(ModelColumns.effort)) {
                $0.isEmpty ? "Default (\(base.effort))" : $0
            }
        }
        .help("Stops after \(EnginePane.seconds(level)) s")
    }

    private func options(_ values: [String], saved path: KeyPath<ProviderModel, String>) -> [String] {
        let saved = models[level]?[keyPath: path] ?? ""
        return values + (saved.isEmpty || values.contains(saved) ? [] : [saved])
    }

    private func field(_ path: WritableKeyPath<ProviderModel, String>) -> Binding<String> {
        Binding(get: { models[level]?[keyPath: path] ?? "" },
                set: { models[level, default: ProviderModel()][keyPath: path] = $0 })
    }
}

/// The custom API rows of the Provider section.
private struct CustomAPISection: View {
    @Binding var custom: CustomProviderSettings
    /// Lifted into EnginePane, which shows it in the Provider section's footer.
    @Binding var keyError: Bool
    @ObservedObject private var state = AppState.shared
    @State private var key = ""
    @State private var confirmRemove = false
    /// Bumped on save and remove, so the view reads the Keychain again.
    @State private var keyVersion = 0

    var body: some View {
        LabeledContent("Base URL") {
            HStack {
                TextField("Base URL", text: $custom.baseURL, prompt: Text("https://openrouter.ai/api/v1")).labelsHidden()
                PullDownButton("Presets") {
                    CustomProviderSettings.presets.map { preset in .action("\(preset.name): \(preset.url)") { custom.baseURL = preset.url } }
                }
                .fixedSize()
            }
        }
        LabeledContent("API Key") {
            HStack {
                SecureField("API Key", text: $key, prompt: Text(keyPrompt)).labelsHidden()
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
}

/// The Models rows for the custom API: each level's model id and optional effort.
private struct CustomModelsSection: View {
    @Binding var custom: CustomProviderSettings

    var body: some View {
        ForEach(Level.allCases, id: \.self) { level in
            IconRow(symbol: symbol(level).name, tint: symbol(level).tint, title: level.title, titleWidth: ModelColumns.title) {
                TextField("\(level.title) Model", text: field(level, \.model), prompt: Text("Model id")).frame(maxWidth: .infinity)
                TextField("\(level.title) Effort", text: field(level, \.effort), prompt: Text("Effort (optional)"))
                    .frame(width: ModelColumns.effort)
                    .help("Sent as reasoning_effort")
            }
            .labelsHidden()
            .help("Stops after \(EnginePane.seconds(level)) s")
        }
    }

    private func field(_ level: Level, _ path: WritableKeyPath<ProviderModel, String>) -> Binding<String> {
        Binding(get: { custom.models[level]?[keyPath: path] ?? "" },
                set: { custom.models[level, default: ProviderModel()][keyPath: path] = $0 })
    }
}

/// The Models rows' symbol and tint for a level.
private func symbol(_ level: Level) -> (name: String, tint: Color) {
    switch level {
    case .medium: ("gauge.with.dots.needle.33percent", .green)
    case .high: ("gauge.with.dots.needle.67percent", .blue)
    case .max: ("gauge.with.dots.needle.100percent", .purple)
    }
}
