import AppKit
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
            // Lowering retention asks first (Settings → History); this only applies the answer.
            if settings.historyRetention != oldValue.historyRetention {
                history.trim(to: settings.historyRetention.memoryLimit)
                scheduleHistorySave()
            }
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
    /// Saved off the main thread half a second after the last change, so recording a result never delays the paste.
    @Published var history: History { didSet { scheduleHistorySave() } }
    @Published var usage: Usage { didSet { if !AppWindows.isDemo { usage.save(to: Store.url("usage.json")) } } }

    private init() {
        if AppWindows.isDemo {
            settings = DemoData.settings
            history = DemoData.history
            usage = DemoData.usage
            return
        }
        let settings = RetextSettings.load(from: Store.url("settings.json"))
        self.settings = settings
        // Off: nothing is read back; a file over the limit (left by an older version with history off, or edited by hand) is
        // trimmed on disk too, so Off never leaves results there that the History page can't show or clear.
        let saved = History.load(from: Store.url("history.json"))
        history = saved.persisted(for: settings.historyRetention)
        usage = Usage.load(from: Store.url("usage.json"))
        if history != saved { scheduleHistorySave() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppState.shared.flushHistory() }
        }
    }

    private var historySave: Task<Void, Never>?
    /// One serial queue, so writes land in the order they were made.
    private static let historyQueue = DispatchQueue(label: "dev.hapd.retext.history", qos: .utility)

    private func scheduleHistorySave() {
        guard !AppWindows.isDemo else { return }
        historySave?.cancel()
        historySave = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            writeHistory(wait: false)
        }
    }

    /// Writes a pending change now and waits for writes already queued, before Retext quits.
    private func flushHistory() {
        if let pending = historySave {
            pending.cancel()
            writeHistory(wait: true)
        } else {
            Self.historyQueue.sync {}
        }
    }

    private func writeHistory(wait: Bool) {
        historySave = nil
        let snapshot = history.persisted(for: settings.historyRetention), url = Store.url("history.json")
        if wait { Self.historyQueue.sync { snapshot.save(to: url) } } else { Self.historyQueue.async { snapshot.save(to: url) } }
    }

    /// "Check for Updates…": opens Settings on About, which shows the answer, and checks there.
    func checkForUpdatesInSettings() {
        SettingsWindow.shared.show(.about)
        checkForUpdatesNow()
    }

    /// Asks GitHub now, unless a manual check is already running. Kept here, not in the About pane, so the check
    /// and its answer outlive the pane: "Check for Updates…" starts it as About opens, and switching panes keeps it.
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
