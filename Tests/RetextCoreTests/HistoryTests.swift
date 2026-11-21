import Foundation
import Testing
@testable import RetextCore

@Suite struct HistoryUsageTests {
    func entry(_ key: String) -> HistoryEntry {
        HistoryEntry(key: key, appName: "TextEdit", title: "Fix", input: "a", output: "b", level: .medium, model: Model.haiku,
                     inputTokens: 1, outputTokens: 1, costUSD: 0.001)
    }

    @Test func retentionCapsNewestFirst() {
        for (retention, kept) in [(HistoryRetention.last20, 20), (.last60, 60), (.unlimited, 75)] {
            var history = History()
            for i in 0..<75 { history.add(entry("k\(i)"), retention: retention) }
            #expect(history.entries.count == kept)
            #expect(history.entries.first?.key == "k74")
            #expect(history.lookup("k\(75 - kept)") != nil && history.lookup("k\(74 - kept)") == nil)
        }
        // Re-running the same key moves it to the top instead of adding a second entry.
        var history = History()
        history.add(entry("a"), retention: .last20)
        history.add(entry("b"), retention: .last20)
        history.add(entry("a"), retention: .last20)
        #expect(history.entries.map(\.key) == ["a", "b"])
    }

    @Test func offKeepsOnlyTheLastInMemoryAndNothingOnDisk() throws {
        var history = History()
        for i in 0..<3 { history.add(entry("k\(i)"), retention: .off) }
        #expect(history.entries.map(\.key) == ["k2"])
        #expect(history.lookup("k2")?.output == "b")  // the cache of the last run still works
        #expect(history.persisted(for: .off).entries.isEmpty)
        #expect(history.persisted(for: .last20) == history)
    }

    @Test func loweringRetentionTrims() {
        var history = History()
        for i in 0..<50 { history.add(entry("k\(i)"), retention: .unlimited) }
        #expect(history.persisted(for: .last20).entries.count == 20 && history.entries.count == 50)
        history.trim(to: HistoryRetention.last20.memoryLimit)
        #expect(history.entries.count == 20 && history.entries.first?.key == "k49" && history.entries.last?.key == "k30")
        history.trim(to: HistoryRetention.unlimited.memoryLimit)
        #expect(history.entries.count == 20)
        history.remove(id: history.entries[0].id)
        #expect(history.entries.first?.key == "k48")
    }

    @Test func historyKeepsTheWholeSelectionAndFindsItByCacheKey() throws {
        let long = "  Teh   quick\nbrown fox " + String(repeating: "jumps over the lazy dog ", count: 3000)
        let job = Job(title: "Fix", model: Model.haiku, effort: "low", system: "Fix it.", kind: .grammar)
        let key = Engine.cacheKey(job, baseURL: "", text: long)
        var history = History()
        // A whole second: history.json keeps ISO 8601 dates without fractions.
        history.add(HistoryEntry(key: key, date: Date(timeIntervalSince1970: 1_800_000_000), appName: "Mail",
                                 bundleID: "com.apple.mail", title: "Fix", kind: .grammar, input: long,
                                 output: long, level: .high, provider: .claude, model: Model.haiku, effort: "low",
                                 inputTokens: 1, outputTokens: 1, costUSD: 0, durationSeconds: 2.5), retention: .last20)
        let saved = try #require(history.lookup(Engine.cacheKey(job, baseURL: "", text: long)))
        #expect(saved.input == long && saved.output == long && !saved.isShortened)
        #expect(history.lookup(Engine.cacheKey(job, baseURL: "", text: long + "!")) == nil)
        // Through the file: compact JSON, every field back.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("retext-history-\(UUID()).json")
        history.save(to: url)
        let data = try Data(contentsOf: url)
        #expect(!data.contains(UInt8(ascii: "\n")))
        #expect(History.load(from: url) == history)
    }

    @Test func loadKeepsOlderEntriesAsTheyAre() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("retext-history-\(UUID()).json")
        // history.json as 1.4.0 writes it: pretty-printed, the whole selection, no level.
        let json = #"""
        {
          "entries" : [
            {
              "appName" : "Mail",
              "costUSD" : 0.001,
              "date" : "2026-01-01T00:00:00Z",
              "input" : "Thanks for the quick reply,\nI has attached the file.",
              "inputTokens" : 1,
              "key" : "k",
              "model" : "haiku",
              "output" : "out",
              "outputTokens" : 2,
              "title" : "Fix"
            }
          ]
        }
        """#
        try Data(json.utf8).write(to: url)
        let entry = try #require(History.load(from: url).lookup("k"))
        #expect(entry.input == "Thanks for the quick reply,\nI has attached the file." && entry.output == "out" && entry.outputTokens == 2)
        #expect(!entry.isShortened && entry.level == nil && entry.provider == nil && entry.durationSeconds == nil && entry.kind == nil)
        // Not saved back on load.
        #expect(try String(contentsOf: url, encoding: .utf8) == json)
    }

    @Test func entriesFromBuildsBeforeFullHistoryAreShortened() throws {
        // A build from main between 1.4.0 and full history saved `Engine.normalize(input).prefix(60)` and no level.
        let start = "Thanks for the quick reply, I has attached the file you aske"
        #expect(start.count == HistoryEntry.legacyInputLimit)
        let old = HistoryEntry(key: "k", appName: "Mail", title: "Fix", input: start, output: "out", model: "haiku",
                               inputTokens: 1, outputTokens: 2, costUSD: 0)
        #expect(old.isShortened)
        // The same text with a level is a full-history entry.
        let full = HistoryEntry(key: "k", appName: "Mail", title: "Fix", input: start, output: "out", level: .medium, model: "haiku",
                                inputTokens: 1, outputTokens: 2, costUSD: 0)
        #expect(!full.isShortened)
    }

    @Test func unreadableFileIsKeptAsInvalid() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("retext-history-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("history.json"), invalid = dir.appendingPathComponent("history.json.invalid")
        #expect(History.load(from: url) == History())
        #expect(!FileManager.default.fileExists(atPath: invalid.path))
        try Data("not json".utf8).write(to: url)
        #expect(History.load(from: url) == History())
        #expect(try String(contentsOf: invalid, encoding: .utf8) == "not json")
        // An earlier copy is never overwritten.
        try Data("{\"entries\": 1}".utf8).write(to: url)
        #expect(History.load(from: url) == History())
        #expect(try String(contentsOf: invalid, encoding: .utf8) == "not json")
    }

    @Test func selectionLimit() {
        #expect(Engine.maxSelectionLength == 50_000)
        #expect(!Engine.isTooLong(String(repeating: "a", count: 50_000)))
        #expect(Engine.isTooLong(String(repeating: "a", count: 50_001)))
    }

    @Test func usageCountsCallsAndHits() throws {
        var usage = Usage()
        let output = try #require(ClaudeOutput.parse(Data(#"{"result":"x","total_cost_usd":0.5,"usage":{"input_tokens":10,"output_tokens":2}}"#.utf8)))
        usage.recordCall(model: Model.sonnet, output: output)
        usage.recordCall(model: Model.sonnet, output: output)
        usage.recordHit()
        let today = usage.today
        #expect(today.calls[Model.sonnet] == 2)
        #expect(today.inputTokens == 20 && today.outputTokens == 4)
        #expect(today.cacheHits == 1)
        #expect(today.costUSD == 1.0)
        #expect(Model.shortName("claude-sonnet-5-5") == "Sonnet" && Model.shortName("opus") == "Opus")
        #expect(Model.shortName("claude-opus-5-5") == "Opus" && Model.shortName("other-model") == "other-model")
        usage.recordCall(model: "claude-haiku-4-5-20251001", output: output)
        usage.recordCall(model: Model.haiku, output: output)
        #expect(usage.today.callsByModel.map(\.name) == ["Haiku", "Sonnet"])
        #expect(usage.today.callsByModel.map(\.calls) == [2, 2])
        #expect(usage.today.summary.hasPrefix("Today: Haiku 2, Sonnet 2,"))
        #expect(usage.today.summary.hasSuffix("Claude Code list price"))
        var free = UsageDay()
        free.calls["gpt-6-luna"] = 1
        free.outputTokens = 5
        #expect(free.summary == "Today: gpt-6-luna 1, 0 cached, 5 tokens")
        let decoded = try JSONDecoder().decode(Usage.self, from: JSONEncoder().encode(usage))
        #expect(decoded == usage)
    }

    @Test func usageTotalsOverDays() {
        var usage = Usage()
        let now = Date()
        let output = ClaudeOutput(result: "x", inputTokens: 10, outputTokens: 2, costUSD: 0.5)
        for offset in [0, -6, -7, -29, -30, -89] {
            let date = Usage.calendar.date(byAdding: .day, value: offset, to: now)!
            usage.recordCall(model: Model.haiku, output: output, on: date)
        }
        usage.recordHit(on: now)
        #expect(usage.total(days: 1, now: now).runs == 2)
        #expect(usage.total(days: 7, now: now).runs == 3)
        #expect(usage.total(days: 30, now: now).runs == 5)
        let all = usage.total(days: 90, now: now)
        #expect(all.runs == 7 && all.inputTokens == 60 && all.outputTokens == 12 && all.costUSD == 3.0 && all.cacheHits == 1)
    }

    @Test func usageKeepsOnlyRecentDays() {
        var usage = Usage()
        let now = Date()
        let old = Usage.calendar.date(byAdding: .day, value: -Usage.keepDays, to: now)!
        let edge = Usage.calendar.date(byAdding: .day, value: 1 - Usage.keepDays, to: now)!
        usage.recordHit(on: old)
        usage.recordHit(on: edge)
        usage.recordHit(on: now)
        #expect(usage.days.keys.sorted() == [Usage.dayKey(edge), Usage.dayKey(now)])
        // Gregorian keys even on a Mac set to another calendar (Buddhist would give 2569).
        #expect(Usage.dayKey(Date(timeIntervalSince1970: 1_800_000_000)).hasPrefix("2027-01-"))
    }
}
