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
        settings.onboarded = true
        return settings
    }()

    static let history: History = {
        let samples = [
            ("TextEdit", "Fix grammar", "Their going to the libary tomorow.", "They're going to the library tomorrow."),
            ("Mail", "English", "Merci pour votre aide.", "Thank you for your help."),
            ("Notes", "Shorter", "The meeting that was planned for Monday has been moved to a later date.", "Monday's meeting was postponed."),
            ("Pages", "Friendly", "Send the report by Friday.", "Could you send the report by Friday? Thanks!"),
        ]
        return History(entries: samples.enumerated().map { i, sample in
            HistoryEntry(key: "demo-\(i)", date: Date().addingTimeInterval(Double(-900 * (i + 1))), appName: sample.0, title: sample.1,
                         input: sample.2, output: sample.3, model: Model.haiku, inputTokens: 180 + 20 * i, outputTokens: 12 + 4 * i,
                         costUSD: 0.0012 * Double(i + 1))
        })
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
