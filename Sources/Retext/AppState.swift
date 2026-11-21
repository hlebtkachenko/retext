import Foundation
import RetextCore

/// App-wide state backed by JSON files in ~/Library/Application Support/Retext. A `--demo` run reads and writes none
/// of them: it shows sample data (`DemoData`), so screenshots never show the owner's settings or history.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var settings: RetextSettings {
        didSet {
            if !AppWindows.isDemo { settings.save(to: Store.url("settings.json")) }
            Hotkeys.configure(settings)
            if settings.provider != oldValue.provider || settings.claudePath != oldValue.claudePath
                || settings.codexPath != oldValue.codexPath || settings.custom != oldValue.custom
                || settings.chatGPTModels != oldValue.chatGPTModels { checkProvider() }
        }
    }
    /// The active provider's local check; nil until the first check. The menu shows its problem.
    @Published var providerStatus: ProviderStatus?
    /// A newer release found by `UpdateChecker`; the menu offers it.
    @Published var update: Release?
    /// A manual update check (Check Now, Check for Updates…) is running; a second one is not started.
    @Published private(set) var checkingForUpdates = false
    /// The last manual check's answer, shown in Settings → About.
    @Published var updateCheckResult: UpdateCheckResult?
    @Published var history: History { didSet { if !AppWindows.isDemo { history.save(to: Store.url("history.json")) } } }
    @Published var usage: Usage { didSet { if !AppWindows.isDemo { usage.save(to: Store.url("usage.json")) } } }

    private init() {
        if AppWindows.isDemo {
            settings = DemoData.settings
            history = DemoData.history
            usage = DemoData.usage
            return
        }
        settings = RetextSettings.load(from: Store.url("settings.json"))
        history = History.load(from: Store.url("history.json"))
        usage = Usage.load(from: Store.url("usage.json"))
    }

    /// "Check for Updates…": opens Settings on About, which shows the answer, and checks there.
    func checkForUpdatesInSettings() {
        SettingsWindow.shared.show(.about)
        checkForUpdatesNow()
    }

    /// Asks GitHub now, unless a manual check is already running. Kept here, not in the About pane, so it
    /// survives Settings rebuilding its content when it is opened on a pane.
    func checkForUpdatesNow() {
        guard !checkingForUpdates else { return }
        checkingForUpdates = true
        updateCheckResult = nil
        Task {
            updateCheckResult = await UpdateChecker.checkNow()
            checkingForUpdates = false
        }
    }

    /// Counts provider checks, so a slow older check never overwrites a newer one's answer.
    private var providerCheck = 0

    /// Checks the active provider again (after a settings change, a key change or a failed run).
    func checkProvider() {
        providerCheck += 1
        let generation = providerCheck, settings = settings
        Task.detached {
            let status = ProviderStatus.check(settings)
            await MainActor.run { if AppState.shared.providerCheck == generation { AppState.shared.providerStatus = status } }
        }
    }
}
