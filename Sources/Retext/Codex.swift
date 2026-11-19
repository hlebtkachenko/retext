import Foundation
import RetextCore

/// Runs `codex exec` with the user's own ChatGPT login (Codex CLI). Retext never reads or stores the credentials:
/// a private CODEX_HOME holds only a symlink to Codex's auth.json, which keeps the user's config, AGENTS.md and MCP out
/// of the run, and lets Codex refresh its tokens in the real file. With `Codex.arguments` the run can't run commands,
/// write files (read-only sandbox) or search the web, and gets no skills list.
enum CodexRunner {
    nonisolated private static let candidates: [String] = {
        let nvm = NSString(string: "~/.nvm/versions/node").expandingTildeInPath
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []).sorted(by: >).map { "\(nvm)/\($0)/bin/codex" }
        return ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "~/.local/bin/codex"] + versions
    }()

    nonisolated static func executable(override: String) -> String? {
        CommandLocator.find("codex", override: override, candidates: candidates)
    }

    /// Codex's own home: $CODEX_HOME (the app's or the login shell's), else ~/.codex.
    nonisolated private static let userHome: URL = {
        // Profiles can print noise: only the line with the marker counts.
        let marker = "RETEXT_CODEX_HOME="
        let raw = ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? CommandLocator.loginShell(#"printf 'RETEXT_CODEX_HOME=%s\n' "$CODEX_HOME""#).last { $0.hasPrefix(marker) }.map { String($0.dropFirst(marker.count)) }
        let path = NSString(string: raw ?? "").expandingTildeInPath
        return URL(fileURLWithPath: path.hasPrefix("/") ? path : NSString(string: "~/.codex").expandingTildeInPath)
    }()

    /// Whether Codex has a login to use (auth.json exists; its contents are never read).
    nonisolated static var hasLogin: Bool {
        FileManager.default.fileExists(atPath: userHome.appendingPathComponent("auth.json").path)
    }

    /// ~/Library/Application Support/Retext/codex-home with `auth.json` linked to Codex's own. Throws `notLoggedIn`
    /// when Codex has no login yet.
    nonisolated static func privateHome() throws -> URL {
        let fm = FileManager.default
        let home = Store.url("codex-home")
        let source = userHome.appendingPathComponent("auth.json")
        let link = home.appendingPathComponent("auth.json")
        guard fm.fileExists(atPath: source.path) else { throw ClaudeFailure.notLoggedIn }
        try? fm.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let target = try? fm.destinationOfSymbolicLink(atPath: link.path) {
            if target == source.path { return home }
            try? fm.removeItem(at: link)  // only ever a symlink Retext made, pointing at an older CODEX_HOME
        } else if fm.fileExists(atPath: link.path) {
            return home  // a real file, not ours to replace
        }
        do { try fm.createSymbolicLink(at: link, withDestinationURL: source) } catch { throw ClaudeFailure.other("Can't link Codex's login: \(error.localizedDescription)") }
        return home
    }

    /// The app's environment with CODEX_HOME set, and the codex directory first on PATH: an npm install is a Node
    /// script (`#!/usr/bin/env node`) and node sits next to it, but apps start with a bare PATH.
    nonisolated static func environment(codex path: String, home: URL?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        env["PATH"] = ([dir] + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
                        + ["/opt/homebrew/bin", "/usr/local/bin"]).joined(separator: ":")
        if let home { env["CODEX_HOME"] = home.path }
        return env
    }

    private static func locate(_ codexPath: String) async -> String? {
        await Task.detached { executable(override: codexPath) }.value
    }

    /// Throws `ClaudeFailure`; cancellation and timeout as in `Subprocess.run`.
    static func run(_ job: Job, text: String, codexPath: String, timeout: Duration) async throws -> ClaudeOutput {
        guard let path = await locate(codexPath) else { throw ClaudeFailure.notFound }
        let home = try privateHome()
        try Task.checkCancellation()
        // An empty working directory of its own: Codex reads AGENTS.md from the working directory.
        let work = home.appendingPathComponent("work")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let result = try await Subprocess.run(path, Codex.arguments(model: job.model, effort: job.effort, system: job.system),
                                              input: Data(Engine.wrap(text).utf8), environment: environment(codex: path, home: home),
                                              directory: work, timeout: timeout)
        let parsed = Codex.parse(result.stdout)
        if result.exited, result.status == 0, parsed.error.isEmpty, !parsed.text.isEmpty { return parsed.claudeOutput }
        guard result.exited else { throw ClaudeFailure.other("") }  // cancelled or timed out
        // stderr also carries "Reading additional input from stdin...", which isn't an error.
        let stderr = String(decoding: result.stderr, as: UTF8.self).split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("Reading additional input") }.joined(separator: "\n")
        let message = [parsed.error, stderr].filter { !$0.isEmpty }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        throw Codex.classify(message)
    }

    /// "0.167.2" from `codex --version`.
    static func version(codexPath: String) async -> String? {
        guard let path = await locate(codexPath) else { return nil }
        return await Subprocess.output(path, ["--version"], environment: environment(codex: path, home: nil))?
            .split(whereSeparator: \.isWhitespace).last.map(String.init)
    }

    /// `codex login status`: true for a ChatGPT login, false otherwise, nil when Codex can't be run.
    static func isLoggedInWithChatGPT(codexPath: String) async -> Bool? {
        guard let path = await locate(codexPath) else { return nil }
        guard let home = try? privateHome() else { return false }
        guard let text = await Subprocess.output(path, ["login", "status"], environment: environment(codex: path, home: home)) else { return nil }
        return text.contains("Logged in using ChatGPT")
    }

    /// The models Codex lists for this login (`codex debug models`), or [] when it can't tell.
    static func models(codexPath: String) async -> [String] {
        guard let path = await locate(codexPath), let home = try? privateHome(),
              let result = try? await Subprocess.run(path, ["debug", "models"], input: nil,
                                                     environment: environment(codex: path, home: home), timeout: .seconds(10)),
              result.exited, result.status == 0 else { return [] }
        return Codex.listedModels(result.stdout)
    }
}
