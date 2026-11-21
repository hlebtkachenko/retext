import Foundation
import os
import RetextCore

/// Finds command-line tools the way a Terminal would: apps don't inherit the login shell's PATH.
enum CommandLocator {
    /// Paths found by the login shell. A miss is not kept, so a tool installed later is found without a relaunch.
    static let found = OSAllocatedUnfairLock(initialState: [String: String]())

    /// The override when set (nil if it isn't executable), else `command -v name` in a login shell (cached once found;
    /// a cached path that is no longer executable is dropped and looked up again), else the first executable candidate.
    static func find(_ name: String, override: String, candidates: [String]) -> String? {
        let custom = NSString(string: override.trimmingCharacters(in: .whitespaces)).expandingTildeInPath
        if !custom.isEmpty { return FileManager.default.isExecutableFile(atPath: custom) ? custom : nil }
        if let cached = found.withLock({ $0[name] }) {
            if FileManager.default.isExecutableFile(atPath: cached) { return cached }
            // Uninstalled or moved: forget it, unless another lookup already stored a newer path.
            found.withLock { if $0[name] == cached { $0[name] = nil } }
        }
        // Profiles can print noise: take the last line that is an executable path.
        if let path = loginShell("command -v \(name)").last(where: { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }) {
            found.withLock { $0[name] = path }
            return path
        }
        return candidates.map { NSString(string: $0).expandingTildeInPath }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The output lines of `zsh -lc command`, stopped after 3 s like `Subprocess.run`; a background job the profile
    /// starts can't hold it open. Blocks: call off the main thread.
    static func loginShell(_ command: String) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        let child = Subprocess.Child(p, input: nil)
        let done = DispatchSemaphore(value: 0)
        let output = OSAllocatedUnfairLock(initialState: Data())
        // The completion comes from Dispatch, not the cooperative pool, so waiting on it here can't starve it.
        child.launch { result in
            if case .success(let r) = result { output.withLock { $0 = r.stdout } }
            done.signal()
        }
        if done.wait(timeout: .now() + 3) == .timedOut {
            child.stop()
            done.wait()
        }
        return String(decoding: output.withLock { $0 }, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
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
    /// `directory`: the working directory, default the temporary directory.
    static func run(_ path: String, _ arguments: [String], input: Data?, environment: [String: String]? = nil,
                    directory: URL? = nil, timeout limit: Duration) async throws -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        if let environment { p.environment = environment }
        p.currentDirectoryURL = directory ?? FileManager.default.temporaryDirectory
        let child = Child(p, input: input)
        let timeout = Task { try await Task.sleep(for: limit); child.stop() }
        defer { timeout.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                child.launch { continuation.resume(with: $0) }
            }
        } onCancel: { child.stop() }
    }

    /// stdout and stderr of a short command such as `--version`, or nil when it can't run; stopped after 5 s.
    static func output(_ path: String, _ arguments: [String], environment: [String: String]? = nil) async -> String? {
        guard let result = try? await run(path, arguments, input: nil, environment: environment, timeout: .seconds(5)), result.exited else { return nil }
        return String(decoding: result.stdout + result.stderr, as: UTF8.self)
    }

    /// One child process: collects stdout and stderr as they arrive and reports once, when it has exited and both pipes
    /// reached EOF, or 0.5 s after it exited (a background job it started can keep the pipes open).
    /// `stop` sends SIGTERM, then SIGKILL after 2 s, to its process group.
    final class Child: Sendable {
        typealias Completion = @Sendable (Result<ProcessResult, any Error>) -> Void

        private struct State {
            var launched = false, stopped = false, killScheduled = false, terminated = false
            var outEOF = false, errEOF = false
            var out = Data(), err = Data()
            /// Set while the run is reported to nobody yet; taken exactly once.
            var completion: Completion?
        }

        private let process: Process
        private let input: Data?
        private let stdin = Pipe(), output = Pipe(), errors = Pipe()
        // Launch, stop, the handlers and the report share one lock, so a stop can't hit a process that isn't launched yet.
        private let state = OSAllocatedUnfairLock(initialState: State())

        init(_ process: Process, input: Data?) {
            self.process = process
            self.input = input
        }

        /// Launches the process; `completion` runs exactly once, on a Dispatch thread. A child stopped before launch
        /// never launches and reports `CancellationError`; one that can't launch reports `ClaudeFailure.notFound`.
        func launch(_ completion: @escaping Completion) {
            let p = process
            p.standardInput = input == nil ? FileHandle.nullDevice : stdin
            p.standardOutput = output
            p.standardError = errors
            output.fileHandleForReading.readabilityHandler = { [self] in read($0, stdout: true) }
            errors.fileHandleForReading.readabilityHandler = { [self] in read($0, stdout: false) }
            p.terminationHandler = { [self] _ in
                state.withLock { $0.terminated = true }
                finish(force: false)
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { self.finish(force: true) }
            }
            let failure: (any Error)? = state.withLock { s in
                if s.stopped { return CancellationError() }
                s.completion = completion
                do { try p.run() } catch {
                    s.completion = nil
                    return ClaudeFailure.notFound
                }
                s.launched = true
                return nil
            }
            if let failure {
                detach()
                return completion(.failure(failure))
            }
            if let input {
                let writer = stdin.fileHandleForWriting
                // A child that exits without reading must fail the write, not raise SIGPIPE in Retext.
                _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
                Task.detached {
                    try? writer.write(contentsOf: input)
                    try? writer.close()
                }
            }
        }

        /// Stops the process if it is running: SIGTERM now, SIGKILL after 2 s if it is still running.
        /// Before launch it only marks the child stopped, so it never launches.
        func stop() {
            let signalled = state.withLock { s -> Bool in
                guard !s.terminated else { return false }
                s.stopped = true
                guard s.launched, !s.killScheduled, process.isRunning else { return false }
                s.killScheduled = true
                Self.signal(process.processIdentifier, SIGTERM)
                return true
            }
            guard signalled else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
                state.withLock { _ in if process.isRunning { Self.signal(process.processIdentifier, SIGKILL) } }
            }
        }

        /// The whole group when the child leads one (Foundation starts it in its own), so its children stop too.
        private static func signal(_ pid: pid_t, _ sig: Int32) {
            if getpgid(pid) == pid { killpg(pid, sig) } else { kill(pid, sig) }
        }

        private func read(_ handle: FileHandle, stdout: Bool) {
            let data = handle.availableData
            guard data.isEmpty else {
                return state.withLock { s in if stdout { s.out.append(data) } else { s.err.append(data) } }
            }
            handle.readabilityHandler = nil
            state.withLock { s in if stdout { s.outEOF = true } else { s.errEOF = true } }
            finish(force: false)
        }

        /// Reports the run once it has exited and both pipes are at EOF, or with `force` (the drain time is up).
        private func finish(force: Bool) {
            let report: (Completion, ProcessResult)? = state.withLock { s in
                guard s.terminated, force || (s.outEOF && s.errEOF), let completion = s.completion else { return nil }
                s.completion = nil
                let exited = !s.stopped && process.terminationReason == .exit
                return (completion, ProcessResult(exited: exited, status: process.terminationStatus, stdout: s.out, stderr: s.err))
            }
            guard let (completion, result) = report else { return }
            detach()
            completion(.success(result))
        }

        /// Drops the handlers, which hold this child: a pipe kept open by a background job would keep them alive.
        private func detach() {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
        }
    }
}
