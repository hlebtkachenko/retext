import Foundation

public enum ActionKind: String, Codable, CaseIterable, Sendable {
    case grammar, translate, other
}

public enum ModelChoice: String, Codable, CaseIterable, Sendable {
    case auto, haiku, sonnet
}

/// The shortcut that opens the bar. ⌃⌥Space avoids apps that also use ⌥Space.
public enum MenuShortcut: String, Codable, CaseIterable, Sendable {
    case optionSpace, controlOptionSpace

    public var label: String { self == .optionSpace ? "⌥Space" : "⌃⌥Space" }
}

public struct CustomAction: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var symbol: String
    public var prompt: String
    public var kind: ActionKind
    public var model: ModelChoice

    public init(title: String, symbol: String, prompt: String, kind: ActionKind, model: ModelChoice = .auto) {
        self.title = title
        self.symbol = symbol
        self.prompt = prompt
        self.kind = kind
        self.model = model
    }
}

public struct AppStyle: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var bundleID: String
    public var style: String

    public init(bundleID: String, style: String) {
        self.bundleID = bundleID
        self.style = style
    }
}

/// Everything the user can change in the settings window. Stored as JSON; missing keys fall back to the defaults.
public struct RetextSettings: Codable, Equatable, Sendable {
    public static let maxActions = 9

    public var actions: [CustomAction]
    public var appStyles: [AppStyle]
    public var protectedWords: [String]
    public var menuShortcut = MenuShortcut.optionSpace
    /// Path to the `claude` executable; empty = find it automatically.
    public var claudePath = ""
    /// Off: no results are written to history.json and the cache isn't used.
    public var keepHistory = true
    /// On: AXManualAccessibility is set on every app switch, so ⌥N sees Electron selections before the first bar.
    /// Off: it is set only when Retext reads a selection.
    public var electronSupport = true

    public init(actions: [CustomAction] = RetextSettings.defaultActions,
                appStyles: [AppStyle] = [],
                protectedWords: [String] = []) {
        self.actions = actions
        self.appStyles = appStyles
        self.protectedWords = protectedWords
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RetextSettings()
        actions = try c.decodeIfPresent([CustomAction].self, forKey: .actions) ?? d.actions
        appStyles = try c.decodeIfPresent([AppStyle].self, forKey: .appStyles) ?? d.appStyles
        protectedWords = try c.decodeIfPresent([String].self, forKey: .protectedWords) ?? d.protectedWords
        menuShortcut = (try? c.decodeIfPresent(MenuShortcut.self, forKey: .menuShortcut)) ?? d.menuShortcut
        claudePath = (try? c.decodeIfPresent(String.self, forKey: .claudePath)) ?? d.claudePath
        keepHistory = (try? c.decodeIfPresent(Bool.self, forKey: .keepHistory)) ?? d.keepHistory
        electronSupport = (try? c.decodeIfPresent(Bool.self, forKey: .electronSupport)) ?? d.electronSupport
    }

    public func style(for bundleID: String?) -> String? {
        appStyles.first { $0.bundleID == bundleID && !$0.style.trimmingCharacters(in: .whitespaces).isEmpty }?.style
    }

    /// Fix grammar and English, plus a translation into the Mac's first preferred language when that isn't English.
    public static var defaultActions: [CustomAction] { defaultActions(languages: Locale.preferredLanguages) }

    public static func defaultActions(languages: [String]) -> [CustomAction] {
        var actions = [
            CustomAction(title: "Fix grammar", symbol: "text.badge.checkmark",
                         prompt: grammarPrompt,
                         kind: .grammar),
            CustomAction(title: "English", symbol: "globe",
                         prompt: translatePrompt("English"),
                         kind: .translate),
        ]
        if let code = languages.first.flatMap({ Locale.Language(identifier: $0).languageCode?.identifier }), code != "en",
           let name = Locale(identifier: "en").localizedString(forLanguageCode: code) {
            actions.append(CustomAction(title: name, symbol: "globe",
                                        prompt: translatePrompt(name),
                                        kind: .translate))
        }
        return actions
    }

    public static let grammarPrompt = "Edit the text as a careful native-speaking editor of its language. Fix grammar, spelling and punctuation, and rephrase the parts a native speaker wouldn't say (word-for-word constructions from another language, wrong word choice or collocations, unnatural word order) the way a native would say them. Change nothing else: keep the language, the line breaks, all content, meaning, tone and register, sentence types (questions stay questions), forms of address and their capitalization, and any wording that is already natural. Casual text stays casual: keep its slang, abbreviations, emoji and lowercase style, and fix only real errors. If nothing needs fixing, return the text unchanged."

    /// Asks for meaning, not words: a plain "translate naturally" still gets word-by-word calques from the source language.
    /// These prompts were calibrated over 5 rounds of 60 real-world cases; small wording changes moved results, so re-test after editing.
    public static func translatePrompt(_ language: String) -> String {
        "Translate the text into \(language) the way a native \(language) speaker would write it in the same situation. Convey the meaning and intent, not the words: restructure sentences, reorder words and use idiomatic \(language) phrasing. Never carry over constructions, word order or idioms from the source language. Keep the register (casual stays casual, neutral stays neutral, formal stays formal) and use correct forms of address. Keep all of the meaning, including emphasis and politeness, but render fillers and particles the way \(language) would, or leave them out where \(language) wouldn't use them. Make sure the result is flawless \(language): grammar, spelling, inflection and word order. If the text is already \(language), fix its grammar and rewrite any phrasing a native speaker wouldn't use; leave natural wording as it is."
    }

    // MARK: File

    public static func load(from url: URL) -> RetextSettings {
        guard let data = try? Data(contentsOf: url), var settings = try? JSONDecoder().decode(RetextSettings.self, from: data) else {
            return RetextSettings()
        }
        settings.migrate()
        return settings
    }

    /// 1.2.0 defaults the user never edited move to the current ones; edited prompts and styles stay as they are.
    mutating func migrate() {
        let oldGrammar = "Correct grammar, spelling and punctuation of the text. Keep its language and keep wording that is already correct."
        for i in actions.indices {
            let prompt = actions[i].prompt
            if prompt == oldGrammar {
                actions[i].prompt = Self.grammarPrompt
            } else if let match = prompt.wholeMatch(of: #/Translate the text into natural, correct (.+)\. If it is already (.+), only correct its grammar\./#),
                      match.1 == match.2 {
                actions[i].prompt = Self.translatePrompt(String(match.1))
            }
        }
        appStyles.removeAll { $0.bundleID == "com.apple.mail" && $0.style == "Email etiquette: polite greeting and sign-off, clear paragraphs." }
    }

    public func save(to url: URL) { Store.write(self, to: url) }
}

/// ~/Library/Application Support/Retext: settings.json, history.json, usage.json.
public enum Store {
    public static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Retext", isDirectory: true)
    public static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func write(_ value: some Encodable, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(value).write(to: url, options: .atomic)
    }
}
