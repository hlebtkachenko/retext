import Testing
@testable import RetextCore

@Suite struct TextDiffTests {
    typealias S = TextDiff.Segment

    /// Every diff must rebuild both texts.
    private func diff(_ old: String, _ new: String) -> [S] {
        let segments = TextDiff.words(old: old, new: new)
        #expect(segments.filter { $0.kind != .inserted }.map(\.text).joined() == old)
        #expect(segments.filter { $0.kind != .deleted }.map(\.text).joined() == new)
        return segments
    }

    @Test func identical() {
        #expect(diff("Hello world.", "Hello world.") == [S(.equal, "Hello world.")])
    }

    @Test func empty() {
        #expect(diff("", "") == [])
        #expect(diff("", "New text") == [S(.inserted, "New text")])
        #expect(diff("Old text", "") == [S(.deleted, "Old text")])
    }

    @Test func insert() {
        #expect(diff("I am here", "I am still here") == [S(.equal, "I am "), S(.inserted, "still "), S(.equal, "here")])
    }

    @Test func delete() {
        #expect(diff("It is very big", "It is big") == [S(.equal, "It is "), S(.deleted, "very "), S(.equal, "big")])
    }

    @Test func replaceListsDeletedFirst() {
        #expect(diff("He go home", "He goes home") == [S(.equal, "He "), S(.deleted, "go"), S(.inserted, "goes"), S(.equal, " home")])
    }

    @Test func punctuationIsItsOwnToken() {
        #expect(diff("Hello world", "Hello, world!") == [S(.equal, "Hello"), S(.inserted, ","), S(.equal, " world"), S(.inserted, "!")])
    }

    @Test func multiline() {
        #expect(diff("Line one\nline too\n", "Line one\nline two\n")
                == [S(.equal, "Line one\nline "), S(.deleted, "too"), S(.inserted, "two"), S(.equal, "\n")])
    }

    @Test func textWithoutSpacesFallsBackToCharacters() {
        let segments = diff("今日はとても良い天気ですね散歩に行きましょう", "今日はとても悪い天気ですね散歩に行きましょう")
        #expect(segments == [S(.equal, "今日はとても"), S(.deleted, "良"), S(.inserted, "悪"), S(.equal, "い天気ですね散歩に行きましょう")])
    }

    @Test func emojiAndCombiningMarksStayWhole() {
        _ = diff("Café 👍🏽 ok", "Cafe 👍 ok")
    }

    @Test func hugeChangeFallsBackToBlocks() {
        let old = (0..<1200).map { "a\($0)" }.joined(separator: " ")
        let new = (0..<1200).map { "b\($0)" }.joined(separator: " ")
        let segments = diff(old, new)
        #expect(segments.map(\.kind) == [.deleted, .inserted])
    }
}
