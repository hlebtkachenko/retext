import Foundation

/// The parts of GitHub's `releases/latest` answer the update check uses.
public struct Release: Decodable, Equatable, Sendable {
    public let tag_name: String
    public let html_url: String

    public init(tag_name: String, html_url: String) {
        self.tag_name = tag_name
        self.html_url = html_url
    }

    /// "1.4.0" for the tag "v1.4.0".
    public var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
}

public enum Version {
    /// Whether `candidate` ("v1.4.0" or "1.4.0") is a later version than `current` ("1.3.0"). Missing parts count as 0
    /// (1.4 == 1.4.0); anything that isn't dot-separated numbers is never newer.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parts(candidate), let b = parts(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int]? {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        let bare = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? trimmed.dropFirst() : Substring(trimmed)
        let parts = bare.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        return parts.compactMap { $0 }
    }
}
