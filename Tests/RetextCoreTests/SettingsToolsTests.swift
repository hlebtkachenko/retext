import Foundation
import Testing
@testable import RetextCore

@Suite struct DefaultPromptTests {
    @Test func grammarAndTranslateHaveDefaultsOtherHasNone() {
        #expect(RetextSettings.defaultPrompt(for: CustomAction(title: "Fix", symbol: "x", prompt: "", kind: .grammar)) == RetextSettings.grammarPrompt)
        #expect(RetextSettings.defaultPrompt(for: CustomAction(title: "Czech ", symbol: "x", prompt: "", kind: .translate))
                == RetextSettings.translatePrompt("Czech"))
        #expect(RetextSettings.defaultPrompt(for: CustomAction(title: "Shorter", symbol: "x", prompt: "", kind: .other)) == nil)
    }

    @Test func defaultActionsMatchTheirDefaultPrompts() {
        for action in RetextSettings.defaultActions(languages: ["cs-CZ"]) {
            #expect(RetextSettings.defaultPrompt(for: action) == action.prompt)
        }
    }
}

@Suite struct ProtectedWordListTests {
    @Test func splitsAtCommasAndLineBreaksTrimsAndDedupes() {
        #expect(RetextSettings.terms(in: "Retext, Claude Code\nAfframe\r\n, ,Retext\n\nHAPD ") == ["Retext", "Claude Code", "Afframe", "HAPD"])
        #expect(RetextSettings.terms(in: " \n, ").isEmpty)
    }

    @Test func addsOnlyNewTermsInOrder() {
        var settings = RetextSettings(protectedWords: ["Retext"])
        settings.addProtectedWords("Claude, Retext\nPrague")
        #expect(settings.protectedWords == ["Retext", "Claude", "Prague"])
    }
}

@Suite struct ImportTests {
    @Test func roundTripsAnExport() throws {
        var settings = RetextSettings(protectedWords: ["Retext"])
        settings.defaultLevel = .high
        settings.checkForUpdates = false
        let back = try RetextSettings.imported(from: settings.encoded())
        #expect(back == settings)
    }

    @Test func rejectsOtherJSON() {
        #expect(throws: RetextSettings.ImportError.notSettings) { try RetextSettings.imported(from: Data("{}".utf8)) }
        #expect(throws: RetextSettings.ImportError.notSettings) { try RetextSettings.imported(from: Data(#"{"entries":[]}"#.utf8)) }
        #expect(throws: (any Error).self) { try RetextSettings.imported(from: Data("not json".utf8)) }
        #expect(throws: (any Error).self) { try RetextSettings.imported(from: Data(#"{"actions":[{"title":1}]}"#.utf8)) }
    }

    @Test func capsActionsAtNine() throws {
        let many = RetextSettings(actions: Array(repeating: CustomAction(title: "a", symbol: "x", prompt: "p", kind: .other), count: 12))
        #expect(try RetextSettings.imported(from: many.encoded()).actions.count == RetextSettings.maxActions)
    }

    @Test func onlyANewInstallIsNotOnboarded() throws {
        #expect(RetextSettings().onboarded == false)
        #expect(try JSONDecoder().decode(RetextSettings.self, from: Data(#"{"actions":[]}"#.utf8)).onboarded == true)
        #expect(try JSONDecoder().decode(RetextSettings.self, from: Data(#"{"onboarded":false}"#.utf8)).onboarded == false)
        #expect(try JSONDecoder().decode(RetextSettings.self, from: Data("{}".utf8)).checkForUpdates == true)
    }
}

@Suite struct UpdateCheckTests {
    @Test func comparesVersions() {
        #expect(Version.isNewer("v1.4.0", than: "1.3.0"))
        #expect(Version.isNewer("1.10.0", than: "1.9.9"))
        #expect(Version.isNewer("v2", than: "1.9.9"))
        #expect(Version.isNewer("1.3.1", than: "1.3"))
        #expect(!Version.isNewer("v1.3.0", than: "1.3.0"))
        #expect(!Version.isNewer("1.3", than: "1.3.0"))
        #expect(!Version.isNewer("v1.2.9", than: "1.3.0"))
        #expect(!Version.isNewer("v1.4.0-beta", than: "1.3.0"))
        #expect(!Version.isNewer("", than: "1.3.0"))
        #expect(!Version.isNewer("v1.4.0", than: "dev"))
    }

    @Test func releaseVersionDropsTheV() {
        #expect(Release(tag_name: "v1.4.0", html_url: "").version == "1.4.0")
        #expect(Release(tag_name: "1.4.0", html_url: "").version == "1.4.0")
    }
}
