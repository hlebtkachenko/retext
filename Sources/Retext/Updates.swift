import Foundation
import RetextCore

/// Asks GitHub for the latest release at most once a day, at launch and on wake, and remembers it so a later launch
/// the same day still shows "Update available". Nothing is downloaded: the menu item opens the release page.
@MainActor
enum UpdateChecker {
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    /// `RetextRepository` in Info.plist (`owner/name`), so a fork points the check and the About link at itself.
    static let repository = Identity.repository(Bundle.main.object(forInfoDictionaryKey: "RetextRepository") as? String)
    private static let latestURL = Identity.latestReleaseURL(repository: repository)
    private static let checkedKey = "lastUpdateCheck", versionKey = "latestVersion", pageKey = "latestReleasePage"

    /// The remembered release when it is newer than this build and its page is on GitHub.
    static var available: Release? {
        let defaults = UserDefaults.standard
        guard let current = currentVersion, let version = defaults.string(forKey: versionKey),
              let page = defaults.string(forKey: pageKey), page.hasPrefix("https://github.com/"),
              Version.isNewer(version, than: current) else { return nil }
        return Release(tag_name: version, html_url: page)
    }

    /// Skipped when turned off, in a `swift build` binary (no version) and within a day of the last check.
    static func checkIfDue() {
        let defaults = UserDefaults.standard
        guard AppState.shared.settings.checkForUpdates, let current = currentVersion else { return }
        if let last = defaults.object(forKey: checkedKey) as? Date, Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        var request = URLRequest(url: latestURL, timeoutInterval: 15)
        // Only the app name and version; the ephemeral session adds no cookies or cache.
        request.setValue("Retext/\(current)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        Task {
            guard let (data, response) = try? await URLSession(configuration: .ephemeral).data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = try? JSONDecoder().decode(Release.self, from: data) else { return }
            defaults.set(Date(), forKey: checkedKey)
            defaults.set(release.version, forKey: versionKey)
            defaults.set(release.html_url, forKey: pageKey)
            AppState.shared.update = available
        }
    }
}
