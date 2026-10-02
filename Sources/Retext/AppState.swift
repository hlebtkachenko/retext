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
            if settings.claudePath != oldValue.claudePath { checkClaude() }
        }
    }
    /// False when no `claude` executable was found; the menu then says so.
    @Published var claudeFound = true
    @Published var history: History { didSet { history.save(to: Store.url("history.json")) } }
    @Published var usage: Usage { didSet { usage.save(to: Store.url("usage.json")) } }

    private init() {
        settings = RetextSettings.load(from: Store.url("settings.json"))
        history = History.load(from: Store.url("history.json"))
        usage = Usage.load(from: Store.url("usage.json"))
    }

    func checkClaude() {
        let path = settings.claudePath
        Task.detached {
            let found = ClaudeRunner.executable(override: path) != nil
            await MainActor.run { AppState.shared.claudeFound = found }
        }
    }
}
