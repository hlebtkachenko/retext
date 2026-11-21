import RetextCore
import SwiftUI

// MARK: Usage

struct UsagePane: View {
    let usage: Usage

    var body: some View {
        Form {
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
