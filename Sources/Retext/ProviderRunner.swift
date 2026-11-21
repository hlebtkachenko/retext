import Foundation
import RetextCore

/// Sends a job to its provider's runner.
enum ProviderRunner {
    /// `apiKey` is read only for the custom API, for the endpoint's own host (default: the Keychain).
    static func run(_ job: Job, text: String, settings: RetextSettings, timeout: Duration,
                    apiKey: @Sendable (String) -> String? = Keychain.apiKey(account:)) async throws -> ClaudeOutput {
        switch job.provider {
        case .claude: return try await ClaudeRunner.run(job, text: text, claudePath: settings.claudePath, timeout: timeout)
        case .chatgpt: return try await CodexRunner.run(job, text: text, codexPath: settings.codexPath, timeout: timeout)
        case .custom:
            let output = try await APIRunner.run(job, text: text, custom: settings.custom, key: settings.custom.keyAccount.flatMap(apiKey), timeout: timeout)
            // A truncated answer would replace the selection with part of it.
            if output.isCutOff { throw ClaudeFailure.cutOff }
            return output
        }
    }
}

/// Whether the active provider can run, from local checks only (no request is sent).
struct ProviderStatus: Equatable, Sendable {
    let ready: Bool
    /// Ready: what it uses (a path or a host). Not ready: how to fix it.
    let detail: String
    /// The menu-bar item when not ready.
    let problem: String?

    /// Blocks on the login shell the first time: call off the main thread.
    static func check(_ settings: RetextSettings) -> ProviderStatus {
        switch settings.provider {
        case .claude:
            if let path = ClaudeRunner.executable(override: settings.claudePath) { return .ok(path) }
            return ProviderStatus(ready: false, detail: "Install Claude Code and log in, or set its path in Settings → Engine.",
                                  problem: "Claude Code not found…")
        case .chatgpt:
            guard let path = CodexRunner.executable(override: settings.codexPath) else {
                return ProviderStatus(ready: false, detail: "Install the Codex CLI and sign in with ChatGPT, or set its path in Settings → Engine.",
                                      problem: "Codex not found…")
            }
            guard CodexRunner.hasLogin else {
                return ProviderStatus(ready: false, detail: "Run codex login in Terminal and sign in with ChatGPT. Retext needs Codex's file credential store (the default).", problem: "Codex isn't logged in…")
            }
            return .ok(path)
        case .custom:
            let notSetUp = ProviderStatus(ready: false, detail: "Enter the API's base URL and a model for each level in Settings → Engine.",
                                          problem: "Custom API not set up…")
            guard let url = settings.custom.endpoint, let host = url.host else { return notSetUp }
            guard Level.allCases.allSatisfy({ !settings.model(for: $0).model.isEmpty }) else { return notSetUp }
            if settings.custom.needsHTTPS {
                return ProviderStatus(ready: false, detail: "Use https for this server.", problem: "Custom API needs https…")
            }
            // Local servers (Ollama, LM Studio) take no key; remote APIs need one.
            if !CustomProviderSettings.isLocal(host), !Keychain.hasAPIKey(account: settings.custom.keyAccount) {
                return ProviderStatus(ready: false, detail: "Save the API key for \(host) in Settings → Engine.", problem: "API key missing…")
            }
            return .ok(host)
        }
    }

    private static func ok(_ detail: String) -> ProviderStatus { ProviderStatus(ready: true, detail: detail, problem: nil) }
}
