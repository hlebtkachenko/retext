import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public static let inputLimit = 60
    public var id: String { key + date.description }
    public let key: String
    public let date: Date
    public let appName: String
    public let title: String
    /// The start of the selection (`inputLimit` characters of `Engine.normalize`), enough to recognize it in Recent.
    public let input: String
    public let output: String
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let costUSD: Double

    public init(key: String, date: Date = Date(), appName: String, title: String, input: String, output: String,
                model: String, inputTokens: Int, outputTokens: Int, costUSD: Double) {
        self.key = key
        self.date = date
        self.appName = appName
        self.title = title
        self.input = String(Engine.normalize(input).prefix(Self.inputLimit))
        self.output = output
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
    }
}

extension HistoryEntry {
    /// The same entry through `init`, which shortens `input`.
    var shortened: HistoryEntry {
        HistoryEntry(key: key, date: date, appName: appName, title: title, input: input, output: output, model: model,
                     inputTokens: inputTokens, outputTokens: outputTokens, costUSD: costUSD)
    }
}

/// Cache and history in one list, newest first, capped at `limit` entries.
public struct History: Codable, Equatable, Sendable {
    public static let limit = 20
    public private(set) var entries: [HistoryEntry] = []

    public init(entries: [HistoryEntry] = []) { self.entries = Array(entries.prefix(Self.limit)) }

    public func lookup(_ key: String) -> HistoryEntry? { entries.first { $0.key == key } }

    public mutating func add(_ entry: HistoryEntry) {
        entries.removeAll { $0.key == entry.key }
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(Self.limit))
    }

    /// Older entries kept the whole selection: shortened here and saved back to `url` at once.
    public static func load(from url: URL) -> History {
        let decoded = (try? Data(contentsOf: url)).flatMap { try? Store.decoder.decode(History.self, from: $0) } ?? History()
        let history = History(entries: decoded.entries.map(\.shortened))
        if history != decoded { history.save(to: url) }
        return history
    }

    public func save(to url: URL) { Store.write(self, to: url) }
}

/// Per-day counters. Cost is the list-price equivalent `claude -p` reports, not necessarily what the user pays.
public struct UsageDay: Codable, Equatable, Sendable {
    public var calls: [String: Int] = [:]
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheHits = 0
    public var costUSD = 0.0

    public init() {}

    /// Calls per model family, so aliases and full ids (older entries) count together.
    public var callsByModel: [(name: String, calls: Int)] {
        Dictionary(calls.map { (Model.shortName($0.key), $0.value) }, uniquingKeysWith: +)
            .sorted { $0.key < $1.key }.map { (name: $0.key, calls: $0.value) }
    }

    public var summary: String {
        let models = callsByModel.map { "\($0.name) \($0.calls)" }.joined(separator: ", ")
        let price = costUSD > 0 ? ", ≈ $\(String(format: "%.2f", costUSD)) Claude Code list price" : ""
        return "Today: \(models.isEmpty ? "0 calls" : models), \(cacheHits) cached, \(inputTokens + outputTokens) tokens" + price
    }
}

public struct Usage: Codable, Equatable, Sendable {
    /// Days kept in usage.json; older ones are dropped when a new call or hit is recorded.
    public static let keepDays = 90
    /// Gregorian in the local time zone, whatever calendar the Mac uses, so day keys sort by date.
    public static let calendar = Calendar(identifier: .gregorian)
    public var days: [String: UsageDay] = [:]

    public init() {}

    public static func dayKey(_ date: Date = Date()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public var today: UsageDay { days[Self.dayKey()] ?? UsageDay() }

    public mutating func recordCall(model: String, output: ClaudeOutput, on date: Date = Date()) {
        var day = days[Self.dayKey(date)] ?? UsageDay()
        day.calls[model, default: 0] += 1
        day.inputTokens += output.inputTokens
        day.outputTokens += output.outputTokens
        day.costUSD += output.costUSD
        days[Self.dayKey(date)] = day
        prune(now: date)
    }

    public mutating func recordHit(on date: Date = Date()) {
        days[Self.dayKey(date), default: UsageDay()].cacheHits += 1
        prune(now: date)
    }

    /// Keys are yyyy-MM-dd, so string order is date order.
    private mutating func prune(now: Date) {
        guard let start = Self.calendar.date(byAdding: .day, value: 1 - Self.keepDays, to: now) else { return }
        let cutoff = Self.dayKey(start)
        days = days.filter { $0.key >= cutoff }
    }

    public static func load(from url: URL) -> Usage {
        (try? Data(contentsOf: url)).flatMap { try? Store.decoder.decode(Usage.self, from: $0) } ?? Usage()
    }

    public func save(to url: URL) { Store.write(self, to: url) }
}
