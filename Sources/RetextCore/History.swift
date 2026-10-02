import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { key + date.description }
    public let key: String
    public let date: Date
    public let appName: String
    public let title: String
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
        self.input = input
        self.output = output
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
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

    public static func load(from url: URL) -> History {
        (try? Data(contentsOf: url)).flatMap { try? Store.decoder.decode(History.self, from: $0) } ?? History()
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
        return "Today: \(models.isEmpty ? "0 calls" : models), \(cacheHits) cached, "
            + "\(inputTokens + outputTokens) tokens, ≈ $\(String(format: "%.2f", costUSD)) list price"
    }
}

public struct Usage: Codable, Equatable, Sendable {
    public var days: [String: UsageDay] = [:]

    public init() {}

    public static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
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
    }

    public mutating func recordHit(on date: Date = Date()) {
        days[Self.dayKey(date), default: UsageDay()].cacheHits += 1
    }

    public static func load(from url: URL) -> Usage {
        (try? Data(contentsOf: url)).flatMap { try? Store.decoder.decode(Usage.self, from: $0) } ?? Usage()
    }

    public func save(to url: URL) { Store.write(self, to: url) }
}
