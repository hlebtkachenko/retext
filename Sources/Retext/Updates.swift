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
        Task { if case .success(let release) = await fetch(current: current) { remember(release) } }
    }

    /// Check Now and "Check for Updates…": asks now, whatever the setting and the last check, and remembers the answer like
    /// `checkIfDue`, so the menu's "Update available" item follows it.
    static func checkNow() async -> UpdateCheckResult {
        guard let current = currentVersion else { return .failed("This build has no version number.") }
        switch await fetch(current: current) {
        case .failure(let failure):
            return .failed(failure.reason)
        case .success(let release):
            remember(release)
            if let update = available { return .available(update) }
            // Newer, but its page is not on GitHub: never offered.
            if Version.isNewer(release.version, than: current) { return .failed("The latest release's page is not on github.com.") }
            return .upToDate(current)
        }
    }

    private static func fetch(current: String) async -> Result<Release, UpdateCheckFailure> {
        var request = URLRequest(url: latestURL, timeoutInterval: 15)
        // Only the app name and version; the ephemeral session adds no cookies or cache.
        request.setValue("Retext/\(current)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        } catch {
            return .failure(UpdateCheckFailure(reason: error.localizedDescription))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let reason = switch status {
            // The repository has no release yet.
            case 404: "No release found on GitHub."
            // GitHub answers 403 (or 429) when the unauthenticated hourly limit is used up.
            case 403, 429: "GitHub rate limit reached. Try again later."
            default: "GitHub answered \(status)."
            }
            return .failure(UpdateCheckFailure(reason: reason))
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else {
            return .failure(UpdateCheckFailure(reason: "GitHub's answer could not be read."))
        }
        return .success(release)
    }

    private static func remember(_ release: Release) {
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: checkedKey)
        defaults.set(release.version, forKey: versionKey)
        defaults.set(release.html_url, forKey: pageKey)
        AppState.shared.update = available
    }
}

/// What a manual check reports, in Settings → About.
enum UpdateCheckResult: Sendable {
    /// The current version.
    case upToDate(String)
    /// A newer release whose page is on https://github.com/.
    case available(Release)
    /// Why the check failed.
    case failed(String)
}

struct UpdateCheckFailure: Error, Sendable {
    let reason: String
}
