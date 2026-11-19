import Foundation
import os
import RetextCore

/// Runs `claude -p` with the user's own Claude Code login. User settings, hooks, plugins and MCP are skipped for speed.
/// Setup runs on main; the process I/O runs in a detached task.
@MainActor
final class ClaudeRunner {
    nonisolated private static let candidates = ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        .map { NSString(string: $0).expandingTildeInPath }

    /// `command -v claude` in a login shell, looked up once on first use (apps don't inherit the shell's PATH).
    nonisolated private static let loginShellPath: String? = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v claude"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let timeout = DispatchWorkItem { p.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeout)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        timeout.cancel()
        // Profiles can print noise: take the last line that is an executable path.
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
            .last { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// The override when set (nil if it isn't executable), else the login shell's `claude`, else the usual install paths.
    nonisolated static func executable(override: String) -> String? {
        let custom = NSString(string: override.trimmingCharacters(in: .whitespaces)).expandingTildeInPath
        if !custom.isEmpty { return FileManager.default.isExecutableFile(atPath: custom) ? custom : nil }
        return loginShellPath ?? candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// "2.1.284" from `claude --version`, or nil when it can't be run.
    nonisolated static func version(claudePath: String) async -> String? {
        await Task.detached {
            guard let path = executable(override: claudePath) else { return nil }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = ["--version"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map(String.init)
        }.value
    }

    /// Throws `ClaudeFailure`. Cancelling the calling task, or the timeout (the level's, see `Level.timeout`), stops this
    /// call's own process only; a run cancelled before launch never launches.
    func run(_ job: Job, text: String, claudePath: String, timeout limit: Duration) async throws -> ClaudeOutput {
        let p = Process()
        p.arguments = ["-p", "--model", job.model, "--effort", job.effort, "--output-format", "json",
                       "--setting-sources", "", "--strict-mcp-config", "--tools", "",
                       "--disable-slash-commands", "--no-session-persistence",
                       "--system-prompt", job.system]
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        let input = Pipe(), output = Pipe(), errors = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        // Launch and stop share one lock, so a stop can't hit a process that isn't launched yet (terminate would raise).
        let state = OSAllocatedUnfairLock(initialState: (launched: false, stopped: false))
        let stop: @Sendable () -> Void = {
            state.withLock { s in
                s.stopped = true
                if s.launched, p.isRunning { p.terminate() }
            }
        }
        let timeout = Task { try await Task.sleep(for: limit); stop() }
        defer { timeout.cancel() }

        return try await withTaskCancellationHandler {
            try await Task.detached {
                guard let path = Self.executable(override: claudePath) else { throw ClaudeFailure.notFound }
                p.executableURL = URL(fileURLWithPath: path)
                try state.withLock { s in
                    if s.stopped { throw CancellationError() }
                    do { try p.run() } catch { throw ClaudeFailure.notFound }
                    s.launched = true
                }
                try? input.fileHandleForWriting.write(contentsOf: Data(Engine.wrap(text).utf8))
                try? input.fileHandleForWriting.close()
                // Read stderr alongside stdout so a full stderr pipe can't block the process.
                let stderr = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = await stderr.value
                p.waitUntilExit()
                let parsed = ClaudeOutput.parse(data)
                if p.terminationReason == .exit, p.terminationStatus == 0, let parsed, parsed.is_error != true, !parsed.text.isEmpty {
                    return parsed
                }
                guard p.terminationReason == .exit else { throw ClaudeFailure.other("") }  // cancelled or timed out
                let message = [parsed?.is_error == true ? parsed?.result : nil, String(decoding: errorData, as: UTF8.self)]
                    .compactMap { $0 }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                throw ClaudeFailure.classify(message)
            }.value
        } onCancel: { stop() }
    }
}
