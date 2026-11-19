import Foundation
import RetextCore
import Security

/// Calls an OpenAI-compatible Chat Completions API (Settings → Engine → Custom API).
enum APIRunner {
    /// Throws `ClaudeFailure`. URLSession stops the request when the calling task is cancelled; `timeout` bounds the whole call.
    static func run(_ job: Job, text: String, custom: CustomProviderSettings, key: String?, timeout: Duration) async throws -> ClaudeOutput {
        guard let url = custom.endpoint, !job.model.isEmpty else { throw ClaudeFailure.notFound }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = OpenAICompatible.body(model: job.model, effort: job.effort, system: job.system, user: Engine.wrap(text))
        // A non-streaming answer sends nothing until it is done, so the idle timeout must be as long as the whole call.
        let seconds = Double(timeout.components.seconds)
        request.timeoutInterval = seconds
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = seconds
        config.timeoutIntervalForResource = seconds
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw ClaudeFailure.other("") }
            throw ClaudeFailure.other(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw OpenAICompatible.failure(status: status, body: data) }
        guard let output = OpenAICompatible.parse(data) else { throw ClaudeFailure.classify(OpenAICompatible.errorMessage(data)) }
        return output
    }
}

/// The custom API keys in the login Keychain: generic passwords, one per host (`CustomProviderSettings.keyAccount`),
/// never written to settings.json, logs or the UI.
enum Keychain {
    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "co.hleb.retext", kSecAttrAccount as String: account]
    }

    static func apiKey(account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Whether a key is saved for the account, without reading it (no Keychain prompt).
    static func hasAPIKey(account: String?) -> Bool {
        guard let account else { return false }
        var query = base(account)
        query[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Saves the key, or removes it when `key` is empty. Returns false when the Keychain refused.
    @discardableResult
    static func setAPIKey(_ key: String, account: String) -> Bool {
        let base = base(account)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(key.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
