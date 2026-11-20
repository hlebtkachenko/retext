import Foundation
import RetextCore

/// Runs `claude -p` with the user's own Claude Code login. User settings, hooks, plugins and MCP are skipped for speed.
enum ClaudeRunner {
    nonisolated private static let candidates = ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]

    /// The override when set (nil if it isn't executable), else the login shell's `claude`, else the usual install paths.
    nonisolated static func executable(override: String) -> String? {
        CommandLocator.find("claude", override: override, candidates: candidates)
    }

    /// "2.1.284" from `claude --version`, or nil when it can't be run; stopped after 5 s.
    static func version(claudePath: String) async -> String? {
        guard let path = await Task.detached(operation: { executable(override: claudePath) }).value else { return nil }
        return await Subprocess.output(path, ["--version"])?.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    /// Throws `ClaudeFailure`. Cancelling the calling task, or the timeout (the level's, see `Level.timeout`), stops this
    /// call's own process only; a run cancelled before launch never launches.
    static func run(_ job: Job, text: String, claudePath: String, timeout: Duration) async throws -> ClaudeOutput {
        guard let path = await Task.detached(operation: { executable(override: claudePath) }).value else { throw ClaudeFailure.notFound }
        try Task.checkCancellation()
        let args = ["-p", "--model", job.model, "--effort", job.effort, "--output-format", "json",
                    "--setting-sources", "", "--strict-mcp-config", "--tools", "",
                    "--disable-slash-commands", "--no-session-persistence",
                    "--system-prompt", job.system]
        let result = try await Subprocess.run(path, args, input: Data(Engine.wrap(text).utf8), timeout: timeout)
        let parsed = ClaudeOutput.parse(result.stdout)
        if result.exited, result.status == 0, let parsed, parsed.is_error != true, !parsed.text.isEmpty { return parsed }
        guard result.exited else { throw ClaudeFailure.other("") }  // cancelled or timed out
        let message = [parsed?.is_error == true ? parsed?.result : nil, String(decoding: result.stderr, as: UTF8.self)]
            .compactMap { $0 }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        throw ClaudeFailure.classify(message)
    }
}
