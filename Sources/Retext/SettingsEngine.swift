import AppKit
import RetextCore
import SwiftUI

// MARK: AI

struct EnginePane: View {
    @ObservedObject private var state = AppState.shared
    /// The models `codex debug models` lists, for the ChatGPT model pickers.
    @State private var codexModels: [String] = []

    var body: some View {
        let provider = state.settings.provider
        Form {
            Section {
                IntroCard(symbol: "sparkles", title: "How Retext uses AI",
                          text: "The provider is the AI service that edits your text: Claude Code, ChatGPT or an API of your choice, set up once below. Each run uses a quality level: Medium is fast, High rewrites more naturally, Max gives the best result. In the bar, ↑ and ↓ change the level for one run; a run stops after \(Self.seconds(.medium)) s, \(Self.seconds(.max)) s at Max.")
            }
            Section {
                IconRow(symbol: "star.fill", tint: .yellow, title: "Default Level", subtitle: "Every bar opens at it, and ⌥1…⌥9 run at it.") {
                    Picker("Default Level", selection: $state.settings.defaultLevel) {
                        ForEach(Level.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                // Name with its model and role below, the same layout for every level whatever the description's length.
                ForEach(Level.allCases, id: \.self) { level in
                    IconRow(symbol: Self.symbol(level).name, tint: Self.symbol(level).tint, title: level.title, subtitle: describe(level))
                        .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Quality")
            }
            switch provider {
            case .claude: EmptyView()
            case .chatgpt: ChatGPTModelsSection(settings: $state.settings, models: codexModels)
            case .custom: CustomModelsSection(custom: $state.settings.custom)
            }
            Section {
                IconRow(symbol: "cpu", tint: .indigo, title: "Provider", subtitle: Self.about(provider)) {
                    Picker("Provider", selection: $state.settings.provider) {
                        ForEach(Provider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            } header: {
                Text("Setup")
            }
            switch provider {
            case .claude: ClaudeSection(claudePath: $state.settings.claudePath)
            case .chatgpt: ChatGPTSection(settings: $state.settings)
            case .custom: CustomAPISection(custom: $state.settings.custom)
            }
        }
        .onAppear {
            // `--demo settings ai chatgpt|custom` shows another provider's sections; demo settings are never saved.
            if let demo = SettingsView.demoExtra.flatMap(Provider.init(rawValue:)) { state.settings.provider = demo }
        }
        .task(id: provider == .chatgpt ? state.settings.codexPath : nil) {
            guard provider == .chatgpt else { return }
            codexModels = await CodexRunner.models(codexPath: state.settings.codexPath)
        }
    }

    private static func symbol(_ level: Level) -> (name: String, tint: Color) {
        switch level {
        case .medium: ("gauge.with.dots.needle.33percent", .green)
        case .high: ("gauge.with.dots.needle.67percent", .blue)
        case .max: ("gauge.with.dots.needle.100percent", .purple)
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
    @Binding var settings: RetextSettings
    /// nil while checking; then the login state, or nil again when Codex can't be run.
    @State private var loggedIn: Bool??

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
        }
    }
}

/// The per-level ChatGPT models and efforts: a user choice, so above the setup.
private struct ChatGPTModelsSection: View {
    static let efforts = ["low", "medium", "high", "xhigh", "max"]
    @Binding var settings: RetextSettings
    let models: [String]

    var body: some View {
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
            Text("ChatGPT Models")
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

/// The model id for each level of the custom API: a user choice, so above the setup.
private struct CustomModelsSection: View {
    @Binding var custom: CustomProviderSettings

    var body: some View {
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
            Text("Custom API Models")
        } footer: {
            Text("The model id the API expects for each level; effort is sent as reasoning_effort only when set.")
                .foregroundStyle(.secondary)
        }
    }

    private func field(_ level: Level, _ path: WritableKeyPath<ProviderModel, String>) -> Binding<String> {
        Binding(get: { custom.models[level]?[keyPath: path] ?? "" },
                set: { custom.models[level, default: ProviderModel()][keyPath: path] = $0 })
    }
}
