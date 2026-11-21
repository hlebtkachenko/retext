import RetextCore
import SwiftUI

/// Recent results kept for the menu and the cache, with the usage counters below.
struct HistoryPane: View {
    @ObservedObject private var state = AppState.shared
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                // Off or Last 20 for now: History keeps 20 entries whatever the setting.
                Toggle("Keep history", isOn: Binding(get: { state.settings.historyRetention != .off },
                                                     set: { state.settings.historyRetention = $0 ? .last20 : .off }))
                LabeledContent("\(state.history.entries.count) of \(History.limit) saved") {
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                        .foregroundStyle(.red)
                        .disabled(state.history.entries.isEmpty)
                }
            } header: {
                Text("History")
            } footer: {
                Text("The last \(History.limit) results and the first \(HistoryEntry.inputLimit) characters of each selection are kept in plain text in ~/Library/Application Support/Retext/history.json for Recent and the cache.")
                    .foregroundStyle(.secondary)
            }
            UsageSections(usage: state.usage)
        }
        .confirmationDialog("Clear the history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { state.history = History() }
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: {
            Text("Recent results and the cache are deleted.")
        }
    }
}

// MARK: Usage

/// Today's counters and the recent days, as sections of the History pane's form.
struct UsageSections: View {
    let usage: Usage

    var body: some View {
        Group {
            Section("Today") {
                let today = usage.today
                ForEach(today.callsByModel, id: \.name) { model in
                    LabeledContent("\(model.name) calls", value: "\(model.calls)")
                }
                if today.calls.isEmpty { LabeledContent("Calls", value: "0") }
                LabeledContent("Cache hits", value: "\(today.cacheHits)")
                LabeledContent("Input tokens", value: today.inputTokens.formatted())
                LabeledContent("Output tokens", value: today.outputTokens.formatted())
                LabeledContent("Price", value: Self.price(today))
            }
            Section {
                ForEach(usage.days.keys.sorted(by: >).prefix(14), id: \.self) { day in
                    LabeledContent(day, value: Self.summary(usage.days[day]!))
                }
            } header: {
                Text("Recent days")
            } footer: {
                Text("The price is the Claude Code list price for the same tokens; ChatGPT and custom API calls count tokens only.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One formatter for every amount, so all rows show the Mac's currency format.
    private static func price(_ day: UsageDay) -> String { day.costUSD.formatted(.currency(code: "USD")) }

    private static func summary(_ day: UsageDay) -> String {
        let calls = day.callsByModel.map { "\($0.name) \($0.calls)" }.joined(separator: ", ")
        return [calls.isEmpty ? "0 calls" : calls, "\(day.cacheHits) cached",
                "\((day.inputTokens + day.outputTokens).formatted()) tokens", price(day)].joined(separator: ", ")
    }
}
