import Foundation
import RetextCore

/// App-wide state backed by JSON files in ~/Library/Application Support/Retext.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var settings: RetextSettings {
        didSet {
            settings.save(to: Store.url("settings.json"))
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
    @Published var history: History { didSet { history.save(to: Store.url("history.json")) } }
    @Published var usage: Usage { didSet { usage.save(to: Store.url("usage.json")) } }

    private init() {
        settings = RetextSettings.load(from: Store.url("settings.json"))
        history = History.load(from: Store.url("history.json"))
        usage = Usage.load(from: Store.url("usage.json"))
    }

    /// Checks the active provider again (after a settings change, a key change or a failed run).
    func checkProvider() {
        let settings = settings
        Task.detached {
            let status = ProviderStatus.check(settings)
            await MainActor.run { if AppState.shared.settings.provider == settings.provider { AppState.shared.providerStatus = status } }
        }
    }
}
