import Foundation
import RetextCore

/// What a `--demo` run shows instead of the files in Application Support: the default settings with sample actions,
/// and a made-up history and usage with neutral placeholder text.
@MainActor
enum DemoData {
    static let settings: RetextSettings = {
        // English only, not the Mac's languages, so the screenshot is the same on every Mac.
        var settings = RetextSettings(actions: RetextSettings.defaultActions(languages: ["en"]) + [
            CustomAction(title: "Shorter", symbol: "scissors", prompt: "Make the text shorter. Keep its meaning, language and tone.", kind: .other),
            CustomAction(title: "Friendly", symbol: "face.smiling", prompt: "Rewrite the text in a warm, friendly tone. Keep its meaning and language.", kind: .other),
        ], protectedWords: ["Retext", "SwiftUI"])
        settings.appStyles = [AppStyle(bundleID: "com.apple.MobileSMS", style: "Casual and short, no greetings."),
                              AppStyle(bundleID: "com.apple.mail", style: "")]
        settings.onboarded = true
        return settings
    }()

    static let history: History = {
        let samples: [(app: String, title: String, kind: ActionKind?, level: Level, input: String, output: String)] = [
            ("Mail", "Fix grammar", .grammar, .medium,
             "Hi Anna, thank you for you're message. I will sent the documents tomorow morning, and we can discuss about it on Friday.",
             "Hi Anna, thank you for your message. I will send the documents tomorrow morning, and we can discuss it on Friday."),
            ("Notes", "Shorter", .other, .high,
             "The meeting that was planned for Monday has been moved to a later date because several people on the team are travelling that week.",
             "Monday's meeting moved to a later date: several team members are travelling."),
            ("TextEdit", "English", .translate, .medium, "Merci pour votre aide et à bientôt.", "Thank you for your help, and see you soon."),
            ("Pages", "Make it friendlier", nil, .max, "Send the report by Friday.", "Could you send the report by Friday? Thanks a lot!"),
            ("TextEdit", "Fix grammar", .grammar, .medium, "Their going to the libary tomorow.", "They're going to the library tomorrow."),
        ]
        var entries = samples.enumerated().map { i, s in
            let model = Provider.claude.defaultModel(s.level)
            return HistoryEntry(key: "demo-\(i)", date: Date().addingTimeInterval(Double(-1_800 * i - 240)), appName: s.app, title: s.title,
                                kind: s.kind, input: s.input, output: s.output, level: s.level, provider: .claude, model: model.model,
                                effort: model.effort, inputTokens: 180 + 40 * i, outputTokens: 24 + 6 * i,
                                costUSD: 0.0012 * Double(i + 1), durationSeconds: 1.4 + 0.7 * Double(i))
        }
        // Saved before full history: no level, only the start of the selection.
        entries.append(HistoryEntry(key: "demo-old", date: Date().addingTimeInterval(-86_400 * 3), appName: "Mail", title: "Fix grammar",
                                    input: "Thanks for the quick reply, I has", output: "Thanks for the quick reply, I have attached the file.",
                                    model: Model.haiku, inputTokens: 160, outputTokens: 18, costUSD: 0.001))
        return History(entries: entries)
    }()

    static let usage: Usage = {
        var usage = Usage()
        for (offset, calls) in [(0, 4), (-1, 9), (-2, 6)] {
            guard let date = Usage.calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            var day = UsageDay()
            day.calls = [Model.haiku: calls, Model.sonnet: calls / 3]
            day.cacheHits = calls / 2
            day.inputTokens = calls * 210
            day.outputTokens = calls * 16
            day.costUSD = Double(calls) * 0.0015
            usage.days[Usage.dayKey(date)] = day
        }
        return usage
    }()
}
