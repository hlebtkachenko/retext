import Foundation
import RetextCore
import Security

/// Calls an OpenAI-compatible Chat Completions API (Settings → Engine → Custom API).
enum APIRunner {
    /// Throws `ClaudeFailure`. URLSession stops the request when the calling task is cancelled; `timeout` bounds the whole call.
    static func run(_ job: Job, text: String, custom: CustomProviderSettings, key: String?, timeout: Duration) async throws -> ClaudeOutput {
        guard let url = custom.endpoint, !job.model.isEmpty else { throw ClaudeFailure.notFound }
        if custom.needsHTTPS { throw ClaudeFailure.other("use https for this server.") }
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
        let session = URLSession(configuration: config, delegate: SameServerRedirects(), delegateQueue: nil)
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
        // A refused redirect ends the call with the 3xx response itself.
        if (300..<400).contains(status), let from = response.url,
           let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
           let to = URL(string: location, relativeTo: from)?.absoluteURL, !OpenAICompatible.allowsRedirect(from: from, to: to) {
            throw ClaudeFailure.other("redirected to another server; check the base URL.")
        }
        guard (200..<300).contains(status) else { throw OpenAICompatible.failure(status: status, body: data) }
        guard let output = OpenAICompatible.parse(data) else { throw ClaudeFailure.classify(OpenAICompatible.errorMessage(data)) }
        return output
    }
}

/// Follows redirects only within the same server (`OpenAICompatible.allowsRedirect`).
private final class SameServerRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let from = response.url, let to = request.url, OpenAICompatible.allowsRedirect(from: from, to: to) else { return nil }
        return request
    }
}

/// The custom API keys in the login Keychain: generic passwords, one per server (`CustomProviderSettings.keyAccount`),
/// never written to settings.json, logs or the UI. The service is the bundle id; keys saved under the legacy service
/// move to it on first read (`KeychainMigration`).
enum Keychain {
    static let service = Bundle.main.bundleIdentifier ?? Identity.bundleID
    private static let legacy = Identity.legacyKeychainService

    private static func base(_ account: String, service: String = service) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func apiKey(account: String) -> String? {
        KeychainMigration.key(account: account, service: service, read: read,
                              save: { key, service, account in save(key, base(account, service: service)) },
                              delete: { service, account in SecItemDelete(base(account, service: service) as CFDictionary) })
    }

    private static func read(service: String, account: String) -> String? {
        var query = base(account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Whether a key is saved for the account (under the current or the legacy service), without reading it
    /// (no Keychain prompt) and without moving it: the move happens on the first real read.
    static func hasAPIKey(account: String?) -> Bool {
        guard let account else { return false }
        let services = service == legacy ? [service] : [service, legacy]
        return services.contains { service in
            var query = base(account, service: service)
            query[kSecReturnAttributes as String] = true
            return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
        }
    }

    /// Saves the key, or removes it when `key` is empty. Returns false when the Keychain refused.
    /// Either way the legacy item for the account goes, so a cleared key can't come back through the move.
    @discardableResult
    static func setAPIKey(_ key: String, account: String) -> Bool {
        let base = base(account)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved: Bool
        if key.isEmpty {
            let status = SecItemDelete(base as CFDictionary)
            saved = status == errSecSuccess || status == errSecItemNotFound
        } else {
            saved = save(key, base)
        }
        if saved, service != legacy { SecItemDelete(self.base(account, service: legacy) as CFDictionary) }
        return saved
    }

    private static func save(_ key: String, _ base: [String: Any]) -> Bool {
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
