import AppKit
import RetextCore
import SwiftUI

/// Retention, the usage totals and the results themselves, newest first; a click opens a result's details.
struct HistoryPane: View {
    @ObservedObject private var state = AppState.shared
    @State private var confirmClear = false
    /// A lower retention that would discard results, waiting for the user's answer.
    @State private var pendingRetention: HistoryRetention?
    @State private var query = ""
    @State private var detail: HistoryEntry?
    /// Rows shown: a grouped Form lays out every row, so an unlimited history is shown a page at a time.
    @State private var shown = HistoryPane.page
    private static let page = 100

    var body: some View {
        ScrollViewReader { proxy in
            form.task {
                // Screenshots of the list: after the first layout, so the form knows where the rows are.
                guard SettingsView.demoExtra == "results" else { return }
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollTo("results", anchor: .top)
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                Picker("Keep", selection: retention) {
                    ForEach(HistoryRetention.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent {
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                        .foregroundStyle(.red)
                        .disabled(state.history.entries.isEmpty)
                } label: {
                    Text(countText)
                }
            } footer: {
                Text(state.settings.historyRetention == .off
                     ? "Not saved; the last result is kept until Retext quits."
                     : "Saved as plain text in ~/Library/Application Support/Retext/history.json.")
                    .foregroundStyle(.secondary)
            }
            UsageSection(usage: state.usage)
            Section {
                if !state.history.entries.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("Search", text: $query, prompt: Text("Search"))
                            .textFieldStyle(.plain).labelsHidden()
                            .onChange(of: query) { shown = Self.page }
                        if !query.isEmpty {
                            Button("Clear Search", systemImage: "xmark.circle.fill") { query = "" }
                                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                        }
                    }
                }
                let items = filtered
                if items.isEmpty {
                    emptyState
                } else {
                    ForEach(items.prefix(shown)) { entry in
                        HistoryRow(entry: entry, open: { detail = entry }, delete: { state.history.remove(id: entry.id) })
                    }
                    if items.count > shown {
                        Button("Show \(items.count - shown) More") { shown += Self.page }
                            .buttonStyle(.borderless)
                            .frame(maxWidth: .infinity)
                    }
                }
            } header: {
                Text("Results")
            }
            .id("results")
        }
        .sheet(item: $detail) { HistoryDetail(entry: $0, showChanges: SettingsView.demoExtra == "changes") }
        .confirmationDialog("Clear the history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { state.history = History() }
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: {
            Text("All saved results are deleted.")
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } })) {
            Button(pendingRetention == .off ? "Turn Off History" : "Delete Older Results", role: .destructive) {
                if let pendingRetention { state.settings.historyRetention = pendingRetention }
                pendingRetention = nil
            }
            Button("Cancel", role: .cancel) { pendingRetention = nil }.keyboardShortcut(.defaultAction)
        } message: {
            Text(confirmMessage)
        }
        .onAppear {
            switch SettingsView.demoExtra {
            case "detail", "changes": detail = state.history.entries.first
            case "old": detail = state.history.entries.last
            case "clear": confirmClear = true
            case "off": pendingRetention = .off
            default: break
            }
        }
    }

    /// Lowering retention below the number of saved results, or turning it off, asks first.
    private var retention: Binding<HistoryRetention> {
        Binding(get: { state.settings.historyRetention }, set: { new in
            let count = state.history.entries.count
            let discards = new == .off ? count > 0 : new.limit.map { count > $0 } ?? false
            if discards { pendingRetention = new } else { state.settings.historyRetention = new }
        })
    }

    private var countText: String {
        let count = state.history.entries.count
        return count == 1 ? "1 result" : "\(count) results"
    }

    private var confirmTitle: String {
        pendingRetention == .off ? "Turn off history?" : "Keep only the \(pendingRetention?.title.lowercased() ?? "")?"
    }

    private var confirmMessage: String {
        guard let pendingRetention else { return "" }
        if pendingRetention == .off { return "Saved results are deleted." }
        let extra = state.history.entries.count - (pendingRetention.limit ?? 0)
        return "The \(extra) older \(extra == 1 ? "result is" : "results are") deleted."
    }

    private var filtered: [HistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return state.history.entries }
        return state.history.entries.filter { entry in
            [entry.output, entry.input, entry.title, entry.appName].contains { $0.localizedStandardContains(query) }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if state.history.entries.isEmpty {
            ContentUnavailableView("No Results Yet", systemImage: "clock.arrow.circlepath",
                                   description: Text("Results appear here after you run an action or an instruction."))
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}

// MARK: Row

/// One result: its start, the original's start and what made it. Copy and Delete on the row and in its context menu.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    // A prefix, so a 50,000-character result never lays out in full for three lines.
                    Text(entry.output.prefix(400)).lineLimit(3)
                    Text(entry.input.prefix(300)).lineLimit(2).foregroundStyle(.secondary)
                    Text(entry.metadata).font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.title), \(entry.appName)")
            .accessibilityValue(String(entry.output.prefix(400)))
            .accessibilityHint("Shows the details")
            HStack(spacing: 2) {
                Button("Copy Result", systemImage: "doc.on.doc") { HistoryEntry.copy(entry.output) }.help("Copy Result")
                Button("Copy Original", systemImage: "text.quote") { HistoryEntry.copy(entry.input) }.help("Copy Original")
                Button("Delete", systemImage: "trash", action: delete).help("Delete")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .controlSize(.large)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Show Details", action: open)
            Divider()
            Button("Copy Result") { HistoryEntry.copy(entry.output) }
            Button("Copy Original") { HistoryEntry.copy(entry.input) }
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
    }
}

extension HistoryEntry {
    /// "Fix grammar · Mail · 5 minutes ago · High · 1.8 s"; older entries have no level or duration and say so.
    var metadata: String {
        var parts = [title, appName, date.formatted(.relative(presentation: .named).locale(Self.english))]
        if let level { parts.append(level.title) }
        if let durationSeconds { parts.append(Self.seconds(durationSeconds)) }
        if isShortened { parts.append("Only the start was saved") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Dates in words in English, like the rest of the UI, with the Mac's region for the order and clock.
    static let english = Locale(languageCode: .english, languageRegion: Locale.current.region)

    static func seconds(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) + " s" }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: Detail

/// A result in full: the original, the result (optionally with its changes marked) and how it was made.
private struct HistoryDetail: View {
    let entry: HistoryEntry
    @State var showChanges = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(entry.title).font(.title3.bold()).lineLimit(1)
                Spacer()
                // Older entries kept only the start of the original: a diff against it would mark nearly everything.
                Toggle("Show Changes", isOn: $showChanges).toggleStyle(.switch).disabled(entry.isShortened)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 4)
            Form {
                Section {
                    Text(entry.input)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if entry.isShortened {
                        Label("Only the start was saved.", systemImage: "info.circle").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Original")
                }
                Section {
                    // The diff is worked out only when asked for: a long text takes a moment.
                    let segments = showChanges ? TextDiff.words(old: entry.input, new: entry.output) : nil
                    Group {
                        if let segments {
                            Text(PopupView.marked(segments)).accessibilityLabel(PopupView.spoken(segments))
                        } else {
                            Text(entry.output)
                        }
                    }
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Result")
                }
                Section("Details") {
                    LabeledContent("Date", value: entry.date.formatted(Date.FormatStyle(date: .complete, time: .standard).locale(HistoryEntry.english)))
                    LabeledContent("Action", value: entry.kind == nil && entry.level != nil ? "Instruction: \(entry.title)" : entry.title)
                    if !entry.appName.isEmpty { LabeledContent("App", value: entry.appName) }
                    if let provider = entry.provider { LabeledContent("Provider", value: provider.title) }
                    LabeledContent("Model", value: entry.model)
                    if let level = entry.level {
                        let effort = entry.effort.flatMap { $0.isEmpty ? nil : $0 }
                        LabeledContent("Level", value: effort.map { "\(level.title), \($0) effort" } ?? level.title)
                    }
                    LabeledContent("Tokens", value: "\(entry.inputTokens.formatted()) in, \(entry.outputTokens.formatted()) out")
                    if entry.costUSD > 0 {
                        LabeledContent("Price", value: entry.costUSD.formatted(.currency(code: "USD").precision(.fractionLength(4))))
                    }
                    if let duration = entry.durationSeconds { LabeledContent("Duration", value: HistoryEntry.seconds(duration)) }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Copy Original") { HistoryEntry.copy(entry.input) }
                Button("Copy Result") { HistoryEntry.copy(entry.output) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 600)
    }
}

// MARK: Usage

/// Totals from usage.json: today and the last 7, 30 and 90 days.
private struct UsageSection: View {
    let usage: Usage

    var body: some View {
        Section {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("").gridColumnAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Runs")
                    Text("Tokens")
                    Text("Price")
                }
                .font(.callout).foregroundStyle(.secondary)
                .accessibilityHidden(true)
                ForEach([(1, "Today"), (7, "Last 7 days"), (30, "Last 30 days"), (90, "Last 90 days")], id: \.0) { days, title in
                    let total = usage.total(days: days)
                    GridRow {
                        Text(title)
                        Text(total.runs.formatted())
                        Text((total.inputTokens + total.outputTokens).formatted())
                        Text(total.costUSD.formatted(.currency(code: "USD")))
                    }
                    .monospacedDigit()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(title): \(total.runs) runs, \(total.inputTokens + total.outputTokens) tokens, "
                                        + total.costUSD.formatted(.currency(code: "USD")))
                }
            }
        } header: {
            Text("Usage")
        } footer: {
            Text("Price is the Claude Code list price. ChatGPT and custom API runs count tokens only.")
                .foregroundStyle(.secondary)
        }
    }
}
