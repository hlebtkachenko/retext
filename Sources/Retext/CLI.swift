import Foundation
import os
import RetextCore

/// Finds command-line tools the way a Terminal would: apps don't inherit the login shell's PATH.
enum CommandLocator {
    private static let found = OSAllocatedUnfairLock(initialState: [String: String?]())

    /// The override when set (nil if it isn't executable), else `command -v name` in a login shell (once per name),
    /// else the first executable candidate.
    static func find(_ name: String, override: String, candidates: [String]) -> String? {
        let custom = NSString(string: override.trimmingCharacters(in: .whitespaces)).expandingTildeInPath
        if !custom.isEmpty { return FileManager.default.isExecutableFile(atPath: custom) ? custom : nil }
        let shell: String? = found.withLock { $0[name] } ?? {
            // Profiles can print noise: take the last line that is an executable path.
            let path = loginShell("command -v \(name)").last { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }
            found.withLock { $0[name] = .some(path) }
            return path
        }()
        return shell ?? candidates.map { NSString(string: $0).expandingTildeInPath }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The output lines of `zsh -lc command`, stopped after 3 s. Blocks: call off the main thread.
    static func loginShell(_ command: String) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let timeout = DispatchWorkItem { p.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeout)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        timeout.cancel()
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
    }
}

/// How a child process ended.
struct ProcessResult: Sendable {
    /// False when it was stopped (cancelled or timed out) instead of exiting.
    let exited: Bool
    let status: Int32
    let stdout: Data
    let stderr: Data
}

enum Subprocess {
    /// Runs `path` with `input` on stdin. Cancelling the calling task, or the timeout, stops this call's own process only;
    /// a run cancelled before launch never launches. Throws `ClaudeFailure.notFound` when it can't be launched.
    static func run(_ path: String, _ arguments: [String], input: Data?, environment: [String: String]? = nil,
                    timeout limit: Duration) async throws -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        if let environment { p.environment = environment }
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        let stdin = Pipe(), output = Pipe(), errors = Pipe()
        p.standardInput = input == nil ? FileHandle.nullDevice : stdin
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
                try state.withLock { s in
                    if s.stopped { throw CancellationError() }
                    do { try p.run() } catch { throw ClaudeFailure.notFound }
                    s.launched = true
                }
                if let input {
                    try? stdin.fileHandleForWriting.write(contentsOf: input)
                    try? stdin.fileHandleForWriting.close()
                }
                // Read stderr alongside stdout so a full stderr pipe can't block the process.
                let stderr = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = await stderr.value
                p.waitUntilExit()
                return ProcessResult(exited: p.terminationReason == .exit, status: p.terminationStatus, stdout: data, stderr: errorData)
            }.value
        } onCancel: { stop() }
    }

    /// stdout and stderr of a short command such as `--version`, or nil when it can't run; stopped after 5 s.
    static func output(_ path: String, _ arguments: [String], environment: [String: String]? = nil) async -> String? {
        guard let result = try? await run(path, arguments, input: nil, environment: environment, timeout: .seconds(5)), result.exited else { return nil }
        return String(decoding: result.stdout + result.stderr, as: UTF8.self)
    }
}
