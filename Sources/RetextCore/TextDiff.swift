import Foundation

/// A word-level diff for the preview: which words a result keeps, adds and removes.
public enum TextDiff {
    public enum Kind: Sendable { case equal, inserted, deleted }

    public struct Segment: Equatable, Sendable {
        public let kind: Kind
        public let text: String

        public init(_ kind: Kind, _ text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Words longer than this are compared character by character: text without spaces (Chinese, Japanese, Thai) is one "word".
    static let longWord = 16
    /// Above this many LCS cells the changed middle is shown as removed, then added, instead of word by word.
    /// 16M cells cover a ~1500-word email changed throughout (about 32 MB of UInt16 for a moment).
    static let maxCells = 16_000_000

    /// Equal, deleted and inserted runs in order; equal + deleted text is `old`, equal + inserted text is `new`.
    /// A replacement lists the deleted run before the inserted one.
    public static func words(old: String, new: String) -> [Segment] {
        let a = tokens(old), b = tokens(new)
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let x = Array(a[prefix..<(a.count - suffix)]), y = Array(b[prefix..<(b.count - suffix)])
        // The LCS compares integer ids, not strings: millions of comparisons run on the main thread.
        var ids: [String: Int] = [:]
        func id(_ token: String) -> Int {
            if let id = ids[token] { return id }
            ids[token] = ids.count
            return ids.count - 1
        }
        let xi = x.map(id), yi = y.map(id)

        // Each run collects its tokens and is joined once at the end: appending to the run's string would copy it per token.
        var runs: [(kind: Kind, tokens: [String])] = []
        func add(_ kind: Kind, _ token: String) {
            if runs.last?.kind == kind { runs[runs.count - 1].tokens.append(token) } else { runs.append((kind, [token])) }
        }
        a[..<prefix].forEach { add(.equal, $0) }
        if x.count * y.count > maxCells {
            x.forEach { add(.deleted, $0) }
            y.forEach { add(.inserted, $0) }
        } else {
            // lcs[i * w + j] = longest common subsequence of x[i...] and y[j...]; it is at most min(x, y) <= sqrt(maxCells),
            // so UInt16 holds it.
            let w = y.count + 1
            var lcs = [UInt16](repeating: 0, count: (x.count + 1) * w)
            for i in stride(from: x.count - 1, through: 0, by: -1) {
                for j in stride(from: y.count - 1, through: 0, by: -1) {
                    lcs[i * w + j] = xi[i] == yi[j] ? lcs[(i + 1) * w + j + 1] + 1 : max(lcs[(i + 1) * w + j], lcs[i * w + j + 1])
                }
            }
            var i = 0, j = 0
            while i < x.count || j < y.count {
                if i < x.count, j < y.count, xi[i] == yi[j] {
                    add(.equal, x[i]); i += 1; j += 1
                } else if j == y.count || (i < x.count && lcs[(i + 1) * w + j] >= lcs[i * w + j + 1]) {
                    add(.deleted, x[i]); i += 1
                } else {
                    add(.inserted, y[j]); j += 1
                }
            }
        }
        a[(a.count - suffix)...].forEach { add(.equal, $0) }
        return runs.map { Segment($0.kind, $0.tokens.joined()) }
    }

    /// Runs of letters and digits, runs of whitespace, and single other characters (punctuation, symbols, emoji).
    /// A run longer than `longWord` is split into its characters.
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var run = "", runIsWord = false
        func flush() {
            if runIsWord, run.count > longWord { out += run.map(String.init) } else if !run.isEmpty { out.append(run) }
            run = ""
        }
        for c in text {
            let isWord = c.isLetter || c.isNumber
            if c.isWhitespace {
                if runIsWord || run.first?.isWhitespace == false { flush() }
                runIsWord = false
                run.append(c)
            } else if isWord {
                if !runIsWord { flush() }
                runIsWord = true
                run.append(c)
            } else {
                flush()
                runIsWord = false
                out.append(String(c))
            }
        }
        flush()
        return out
    }
}
