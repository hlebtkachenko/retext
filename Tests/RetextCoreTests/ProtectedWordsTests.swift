import Testing
@testable import RetextCore

@Suite struct ProtectedWordEditTests {
    private func edited(_ words: [String], _ old: String, to text: String) -> [String] {
        var settings = RetextSettings(protectedWords: words)
        settings.editProtectedWord(old, to: text)
        return settings.protectedWords
    }

    @Test func renamesInPlace() {
        #expect(edited(["Acme", "Retext", "Globex"], "Retext", to: " ReText ") == ["Acme", "ReText", "Globex"])
    }

    @Test func splitsAtCommasAndLineBreaksInPlace() {
        #expect(edited(["Acme", "Retext", "Globex"], "Retext", to: "Retext, Claude Code\nCodex") == ["Acme", "Retext", "Claude Code", "Codex", "Globex"])
    }

    @Test func duplicateOfAnotherRowDropsTheEditedRow() {
        #expect(edited(["Acme", "Retext", "Globex"], "Retext", to: "Globex") == ["Acme", "Globex"])
        #expect(edited(["Acme", "Retext", "Globex"], "Retext", to: "Acme, Initech") == ["Acme", "Initech", "Globex"])
    }

    @Test func emptyRemovesTheRow() {
        #expect(edited(["Acme", "Retext"], "Acme", to: "") == ["Retext"])
        #expect(edited(["Acme", "Retext"], "Acme", to: " ,\n ") == ["Retext"])
    }

    @Test func unchangedOrUnknownChangesNothing() {
        #expect(edited(["Acme", "Retext"], "Acme", to: "Acme") == ["Acme", "Retext"])
        #expect(edited(["Acme", "Retext"], "Missing", to: "Other") == ["Acme", "Retext"])
    }

    @Test func comparesExactlyLikeAdding() {
        #expect(edited(["Acme", "Retext"], "Acme", to: "retext") == ["retext", "Retext"])
    }

    @Test func committingTwiceIsHarmless() {
        var settings = RetextSettings(protectedWords: ["Acme", "Retext"])
        settings.editProtectedWord("Acme", to: "Initech")
        settings.editProtectedWord("Acme", to: "Initech")
        #expect(settings.protectedWords == ["Initech", "Retext"])
    }
}
