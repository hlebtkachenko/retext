import Foundation

/// One result: the whole selection, the whole answer and how it was made. The fields added after 1.4.0 are optional, so
/// older files decode: 1.4.0 and earlier saved the whole selection without a `level`; builds from main between 1.4.0 and
/// full history saved only its first `legacyInputLimit` characters (normalized), also without a `level`.
public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { key + date.description }
    /// The cache key (`Engine.cacheKey`): provider, model, effort, prompt and the whole selection.
    public let key: String
    public let date: Date
    public let appName: String
    public let title: String
    /// The selection as it was read, unchanged.
    public let input: String
    public let output: String
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let costUSD: Double
    public let bundleID: String?
    /// nil for a typed instruction (and older entries).
    public let kind: ActionKind?
    /// nil only for entries saved before full history.
    public let level: Level?
    public let provider: Provider?
    public let effort: String?
    /// The provider's run, from the request to the answer.
    public let durationSeconds: Double?

    public init(key: String, date: Date = Date(), appName: String, bundleID: String? = nil, title: String, kind: ActionKind? = nil,
                input: String, output: String, level: Level? = nil, provider: Provider? = nil, model: String, effort: String? = nil,
                inputTokens: Int, outputTokens: Int, costUSD: Double, durationSeconds: Double? = nil) {
        self.key = key
        self.date = date
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.kind = kind
        self.input = input
        self.output = output
        self.level = level
        self.provider = provider
        self.model = model
        self.effort = effort
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.durationSeconds = durationSeconds
    }

    /// How many characters of the selection the builds between 1.4.0 and full history kept.
    public static let legacyInputLimit = 60

    /// Saved by a build between 1.4.0 and full history: `input` is only the start of the selection. A 1.4.0 entry has no
    /// level either, but its whole selection; one that was exactly 60 characters long is marked too, which is harmless.
    public var isShortened: Bool { level == nil && input.count == Self.legacyInputLimit }
}

extension HistoryRetention {
    /// Entries kept in memory: Off still keeps the last one this session (the cache of the last run); nil = no limit.
    public var memoryLimit: Int? { limit.map { max($0, 1) } }
}

/// Cache and history in one list, newest first.
public struct History: Codable, Equatable, Sendable {
    public private(set) var entries: [HistoryEntry] = []

    public init(entries: [HistoryEntry] = []) { self.entries = entries }

    public func lookup(_ key: String) -> HistoryEntry? { entries.first { $0.key == key } }

    /// Adds `entry` first (in place of an entry with the same key) and keeps what `retention` keeps in memory.
    public mutating func add(_ entry: HistoryEntry, retention: HistoryRetention) {
        entries.removeAll { $0.key == entry.key }
        entries.insert(entry, at: 0)
        trim(to: retention.memoryLimit)
    }

    /// Keeps the newest `limit` entries; nil keeps all.
    public mutating func trim(to limit: Int?) {
        if let limit, entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    public mutating func remove(id: HistoryEntry.ID) { entries.removeAll { $0.id == id } }

    /// What history.json holds for `retention`: nothing when Off.
    public func persisted(for retention: HistoryRetention) -> History {
        var copy = self
        copy.trim(to: retention.limit)
        return copy
    }

    /// Older files decode as they are; their shortened inputs are shown as such. A file that can't be decoded is first
    /// copied to `history.json.invalid` next to it (an earlier copy is kept, never overwritten), like settings.json.
    public static func load(from url: URL) -> History {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return History() }
        if let data = try? Data(contentsOf: url), let history = try? decoder.decode(History.self, from: data) { return history }
        let invalid = url.appendingPathExtension("invalid")
        if !fm.fileExists(atPath: invalid.path) { try? fm.copyItem(at: url, to: invalid) }
        return History()
    }

    /// Compact JSON: an unlimited history of long texts is rewritten after every run.
    public func encoded() throws -> Data { try Self.encoder.encode(self) }

    public func save(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoded().write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Per-day counters. Cost is the list-price equivalent `claude -p` reports, not necessarily what the user pays.
public struct UsageDay: Codable, Equatable, Sendable {
    public var calls: [String: Int] = [:]
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheHits = 0
    public var costUSD = 0.0

    public init() {}

    /// Requests sent to a provider plus results taken from the cache.
    public var runs: Int { calls.values.reduce(0, +) + cacheHits }

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

    /// The sum of the last `count` days, today included.
    public func total(days count: Int, now: Date = Date()) -> UsageDay {
        guard let start = Self.calendar.date(byAdding: .day, value: 1 - count, to: now) else { return UsageDay() }
        let first = Self.dayKey(start), last = Self.dayKey(now)
        return days.filter { $0.key >= first && $0.key <= last }.values.reduce(into: UsageDay()) { sum, day in
            sum.calls.merge(day.calls, uniquingKeysWith: +)
            sum.inputTokens += day.inputTokens
            sum.outputTokens += day.outputTokens
            sum.cacheHits += day.cacheHits
            sum.costUSD += day.costUSD
        }
    }

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
