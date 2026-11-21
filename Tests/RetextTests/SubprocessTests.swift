import Foundation
import Testing
@testable import Retext
import RetextCore

/// Serialized: the time bounds would be flaky with the other runs competing for the machine.
@Suite(.serialized) struct SubprocessTests {
    private func sh(_ script: String, input: Data? = nil, timeout: Duration = .seconds(10)) async throws -> (ProcessResult, Duration) {
        let clock = ContinuousClock(), began = clock.now
        let result = try await Subprocess.run("/bin/sh", ["-c", script], input: input, timeout: timeout)
        return (result, clock.now - began)
    }

    @Test func timeoutKillsAChildThatIgnoresTerm() async throws {
        // The shell and its sleep both ignore SIGTERM; SIGKILL to the group must stop them.
        let (result, took) = try await sh("trap '' TERM; sleep 30 & echo $!; wait", timeout: .seconds(1))
        #expect(took < .seconds(4))
        #expect(!result.exited)
        let sleep = try #require(pid_t(String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        try await Task.sleep(for: .milliseconds(200))
        #expect(kill(sleep, 0) != 0, "the background sleep is still running")
    }

    @Test func backgroundJobDoesNotHoldTheRun() async throws {
        let (result, took) = try await sh("sleep 30 & echo hi")
        #expect(took < .seconds(1.5))
        #expect(result.exited)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "hi\n")
    }

    @Test func largeInputRoundTrips() async throws {
        let input = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 % 251) })
        let result = try await Subprocess.run("/bin/cat", [], input: input, timeout: .seconds(10))
        #expect(result.exited)
        #expect(result.status == 0)
        #expect(result.stdout == input)
    }

    @Test func cancelledBeforeLaunchNeverLaunches() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await Subprocess.run("/bin/echo", ["hi"], input: nil, timeout: .seconds(5))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func missingExecutableIsNotFound() async throws {
        await #expect(throws: ClaudeFailure.notFound) {
            try await Subprocess.run("/nonexistent/retext-tool", [], input: nil, timeout: .seconds(5))
        }
    }
}

@Suite struct CommandLocatorTests {
    @Test func missIsNotCached() {
        let name = "retext-missing-tool-\(UInt32.random(in: 0...UInt32.max))"
        #expect(CommandLocator.find(name, override: "", candidates: []) == nil)
        #expect(CommandLocator.found.withLock { $0[name] } == nil)
    }

    @Test func hitIsCached() {
        #expect(CommandLocator.find("ls", override: "", candidates: []) == "/bin/ls")
        #expect(CommandLocator.found.withLock { $0["ls"] } == "/bin/ls")
    }

    @Test func loginShellReturnsOutputLines() {
        #expect(CommandLocator.loginShell("echo one; echo two").suffix(2) == ["one", "two"])
    }
}
