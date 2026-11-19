import Foundation

extension Level {
    /// How long one `claude -p` run may take before it is stopped. Opus at Max needs more time.
    public var timeout: Duration {
        switch self {
        case .medium, .high: .seconds(60)
        case .max: .seconds(120)
        }
    }
}
