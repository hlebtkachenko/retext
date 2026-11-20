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

/// Moves a custom API key from the legacy Keychain service to the current one. The Keychain calls are passed in,
/// so the decision is testable; the key itself is never logged.
public enum KeychainMigration {
    /// The key for `account`: from `service`, else from `legacyService`. A legacy key is saved under `service`, read back,
    /// and only then deleted from `legacyService`; when the save or the check fails, the legacy item stays and its key is used.
    /// - Parameters:
    ///   - read: (service, account) -> key
    ///   - save: (key, service, account) -> success
    ///   - delete: (service, account)
    public static func key(account: String, service: String, legacyService: String = Identity.legacyKeychainService,
                           read: (String, String) -> String?,
                           save: (String, String, String) -> Bool,
                           delete: (String, String) -> Void) -> String? {
        if let key = read(service, account) { return key }
        // Same service: the legacy item is the only copy, never delete it.
        guard service != legacyService, let legacy = read(legacyService, account) else { return nil }
        if save(legacy, service, account), read(service, account) == legacy { delete(legacyService, account) }
        return legacy
    }
}
