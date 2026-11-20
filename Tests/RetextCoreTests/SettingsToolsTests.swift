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
        #expect(RetextSettings.terms(in: "Retext, Claude Code\nAcme\r\n, ,Retext\n\nGlobex ") == ["Retext", "Claude Code", "Acme", "Globex"])
        #expect(RetextSettings.terms(in: " \n, ").isEmpty)
    }

    @Test func addsOnlyNewTermsInOrder() {
        var settings = RetextSettings(protectedWords: ["Retext"])
        settings.addProtectedWords("Claude, Retext\nGlobex")
        #expect(settings.protectedWords == ["Retext", "Claude", "Globex"])
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

    @Test func upgradersSkipTheWelcomeWindow() {
        #expect(RetextSettings.onboardedWithoutSettings(settingsFileExists: false, otherDataExists: false) == false)
        #expect(RetextSettings.onboardedWithoutSettings(settingsFileExists: false, otherDataExists: true) == true)
        #expect(RetextSettings.onboardedWithoutSettings(settingsFileExists: true, otherDataExists: false) == true)
        #expect(RetextSettings.onboardedWithoutSettings(settingsFileExists: true, otherDataExists: true) == true)
    }

    @Test func invalidSettingsAreCopiedAside() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retext-invalid-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.json")
        try Data("not json".utf8).write(to: url)
        let loaded = RetextSettings.load(from: url)
        #expect(loaded.onboarded == true)
        #expect(loaded.actions.map(\.prompt) == RetextSettings.defaultActions.map(\.prompt))
        #expect(try Data(contentsOf: url) == Data("not json".utf8))
        #expect(try Data(contentsOf: directory.appendingPathComponent("settings.json.invalid")) == Data("not json".utf8))
    }

    @Test func missingSettingsWithHistoryCountAsOnboarded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retext-upgrade-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.json")
        #expect(RetextSettings.load(from: url).onboarded == false)
        try Data("{}".utf8).write(to: directory.appendingPathComponent("usage.json"))
        #expect(RetextSettings.load(from: url).onboarded == true)
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
