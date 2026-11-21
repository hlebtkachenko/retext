import Foundation
import Testing
@testable import RetextCore

@Suite struct HistoryUsageTests {
    func entry(_ key: String) -> HistoryEntry {
        HistoryEntry(key: key, appName: "TextEdit", title: "Fix", input: "a", output: "b", model: Model.haiku,
                     inputTokens: 1, outputTokens: 1, costUSD: 0.001)
    }

    @Test func historyIsCappedAndNewestFirst() {
        var history = History()
        for i in 0..<25 { history.add(entry("k\(i)")) }
        #expect(history.entries.count == 20)
        #expect(history.entries.first?.key == "k24")
        #expect(history.lookup("k3") == nil)
        #expect(history.lookup("k10")?.output == "b")
    }

    @Test func historyKeepsOnlyTheStartOfTheInput() throws {
        let long = "  Teh   quick\nbrown fox " + String(repeating: "jumps over the lazy dog ", count: 3000)
        var history = History()
        history.add(HistoryEntry(key: "k", appName: "Mail", title: "Fix", input: long, output: long, model: Model.haiku,
                                 inputTokens: 1, outputTokens: 1, costUSD: 0))
        let saved = try #require(history.lookup("k"))  // the cache key, not the input, finds the entry
        #expect(saved.input.count <= HistoryEntry.inputLimit && saved.input.hasPrefix("Teh quick brown fox jumps"))
        #expect(saved.output == long)
    }

    @Test func loadShortensOlderEntries() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("retext-history-\(UUID()).json")
        let long = String(repeating: "word ", count: 100)
        // An older history.json: the whole selection as input.
        let json = #"{"entries":[{"key":"k","date":"2026-01-01T00:00:00Z","appName":"Mail","title":"Fix","input":"\#(long)","output":"out","model":"haiku","inputTokens":1,"outputTokens":1,"costUSD":0}]}"#
        try Data(json.utf8).write(to: url)
        let entry = try #require(History.load(from: url).lookup("k"))
        #expect(entry.input.count <= HistoryEntry.inputLimit && entry.output == "out")
        // Saved back shortened: the file itself, read without `History.load`.
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let inputs = try #require((object["entries"] as? [[String: Any]])?.map { $0["input"] as? String })
        #expect(!inputs.isEmpty && inputs.allSatisfy { ($0?.count ?? .max) <= HistoryEntry.inputLimit })
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
