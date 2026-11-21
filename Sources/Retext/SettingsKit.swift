import RetextCore
import SwiftUI

/// Runs one tiny request at Medium with the active provider; counted in usage like any other call.
struct TestButton: View {
    let title: String
    /// Extra checks before the request (nil = go on) and a description of what was tested after it.
    var precheck: () async -> ClaudeFailure? = { nil }
    var success: () async -> String = { "Works" }
    @ObservedObject private var state = AppState.shared
    @State private var testing = false
    @State private var result: (ok: Bool, text: String)?

    var body: some View {
        HStack {
            Button(title, action: test).disabled(testing)
            if testing { ProgressView().controlSize(.small) }
            if let result {
                Label(result.text, systemImage: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(result.ok ? Color.green : .orange)
                    .textSelection(.enabled)
            }
        }
    }

    private func test() {
        let settings = state.settings
        testing = true
        result = nil
        Task {
            defer { testing = false }
            let m = settings.model(for: .medium)
            let job = Job(title: "Test", provider: settings.provider, model: m.model, effort: m.effort, system: "Reply with OK.")
            do {
                if let failure = await precheck() { throw failure }
                let output = try await ProviderRunner.run(job, text: "ok", settings: settings, timeout: Level.medium.timeout)
                state.usage.recordCall(model: job.model, output: output)
                try output.checkComplete()
                result = (true, await success())
            } catch {
                let failure = error as? ClaudeFailure ?? .other("")
                result = (false, failure.message(for: settings.provider))
            }
            state.checkProvider()
        }
    }
}
