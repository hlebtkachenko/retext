import Foundation

/// The app's identity: bundle id and GitHub repository. Info.plist holds the real values (`CFBundleIdentifier`,
/// `RetextRepository`), so a fork changes them there; these are the fallbacks for a binary without a bundle.
public enum Identity {
    public static let bundleID = "dev.hapd.retext"
    public static let repository = "hlebtkachenko/retext"
    /// The Keychain service the custom API keys were saved under in 1.4.0 and earlier; read once and moved.
    public static let legacyKeychainService = "co.hleb.retext"

    /// `owner/name` when it looks like a GitHub repository, else the default, so a malformed key can't build a strange URL.
    public static func repository(_ value: String?) -> String {
        guard let value, value.wholeMatch(of: #/[A-Za-z0-9-]+/[A-Za-z0-9._-]+/#) != nil else { return repository }
        return value
    }

    /// GitHub's latest-release endpoint for the repository.
    public static func latestReleaseURL(repository: String) -> URL {
        URL(string: "https://api.github.com/repos/\(self.repository(repository))/releases/latest")!
    }

    /// The repository's page on GitHub.
    public static func pageURL(repository: String) -> URL {
        URL(string: "https://github.com/\(self.repository(repository))")!
    }
}

/// One Keychain read: the key, no such item, or an item that exists but can't be read (access denied, prompt
/// cancelled, Keychain locked, undecodable data).
public enum KeychainRead: Equatable, Sendable {
    case found(String)
    case notFound
    case unavailable
}

/// Moves a custom API key from the legacy Keychain service to the current one. The Keychain calls are passed in,
/// so the decision is testable; the key itself is never logged.
public enum KeychainMigration {
    /// The key for `account`: from `service`, else from `legacyService`. A legacy key is added under `service`, read back,
    /// and only then deleted from `legacyService`. When the add fails (an item already exists, saved meanwhile in Settings,
    /// or the Keychain refused), the legacy item stays and the current item wins if it can be read. When the current item
    /// exists but can't be read, the result is nil and the legacy item is left alone, so a denied read prompts once.
    /// - Parameters:
    ///   - read: (service, account) -> read result
    ///   - save: (key, service, account) -> success; must only add, never overwrite an existing item
    ///   - delete: (service, account)
    public static func key(account: String, service: String, legacyService: String = Identity.legacyKeychainService,
                           read: (String, String) -> KeychainRead,
                           save: (String, String, String) -> Bool,
                           delete: (String, String) -> Void) -> String? {
        switch read(service, account) {
        case .found(let key): return key
        case .unavailable: return nil
        case .notFound: break
        }
        // Same service: the legacy item is the only copy, never delete it.
        guard service != legacyService, case .found(let legacy) = read(legacyService, account) else { return nil }
        guard save(legacy, service, account) else {
            if case .found(let key) = read(service, account) { return key }
            return legacy
        }
        if read(service, account) == .found(legacy) { delete(legacyService, account) }
        return legacy
    }
}
