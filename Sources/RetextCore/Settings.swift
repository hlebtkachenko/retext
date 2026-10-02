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
    /// Grammar actions on model `auto` use Haiku below this many characters, Sonnet from it up.
    public var haikuThreshold: Int
    public var menuShortcut = MenuShortcut.optionSpace
    /// Path to the `claude` executable; empty = find it automatically.
    public var claudePath = ""
    /// Off: no results are written to history.json and the cache isn't used.
    public var keepHistory = true
    /// On: AXManualAccessibility is set on every app switch, so ⌥N sees Electron selections before the first bar.
    /// Off: it is set only when Retext reads a selection.
    public var electronSupport = true

    public init(actions: [CustomAction] = RetextSettings.defaultActions,
                appStyles: [AppStyle] = [AppStyle(bundleID: "com.apple.mail", style: "Email etiquette: polite greeting and sign-off, clear paragraphs.")],
                protectedWords: [String] = [],
                haikuThreshold: Int = 400) {
        self.actions = actions
        self.appStyles = appStyles
        self.protectedWords = protectedWords
        self.haikuThreshold = haikuThreshold
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RetextSettings()
        actions = try c.decodeIfPresent([CustomAction].self, forKey: .actions) ?? d.actions
        appStyles = try c.decodeIfPresent([AppStyle].self, forKey: .appStyles) ?? d.appStyles
        protectedWords = try c.decodeIfPresent([String].self, forKey: .protectedWords) ?? d.protectedWords
        haikuThreshold = try c.decodeIfPresent(Int.self, forKey: .haikuThreshold) ?? d.haikuThreshold
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
                         prompt: "Correct grammar, spelling and punctuation of the text. Keep its language and keep wording that is already correct.",
                         kind: .grammar),
            CustomAction(title: "English", symbol: "globe",
                         prompt: "Translate the text into natural, correct English. If it is already English, only correct its grammar.",
                         kind: .translate),
        ]
        if let code = languages.first.flatMap({ Locale.Language(identifier: $0).languageCode?.identifier }), code != "en",
           let name = Locale(identifier: "en").localizedString(forLanguageCode: code) {
            actions.append(CustomAction(title: name, symbol: "globe",
                                        prompt: "Translate the text into natural, correct \(name). If it is already \(name), only correct its grammar.",
                                        kind: .translate))
        }
        return actions
    }

    // MARK: File

    public static func load(from url: URL) -> RetextSettings {
        guard let data = try? Data(contentsOf: url), let settings = try? JSONDecoder().decode(RetextSettings.self, from: data) else {
            return RetextSettings()
        }
        return settings
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
