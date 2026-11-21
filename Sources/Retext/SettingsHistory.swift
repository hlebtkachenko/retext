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
            PageDescription(.history)
            Section {
                LabeledContent("Keep") {
                    PopUpPicker("Keep", selection: retention, options: HistoryRetention.allCases) { $0.title }.fixedSize()
                }
                LabeledContent("Clear History") {
                    Button("Clear…", role: .destructive) { confirmClear = true }
                        .foregroundStyle(.red)
                        .disabled(state.history.entries.isEmpty)
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
                SectionTitle("History (\(state.history.entries.count))")
            }
            .id("results")
        }
        .sheet(item: $detail) { entry in
            HistoryDetail(entry: entry, showChanges: SettingsView.demoExtra == "changes",
                          delete: { state.history.remove(id: entry.id) })
        }
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

/// One result: its start, the original's start and what made it; a click opens its details, the context menu copies or deletes.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    // A prefix, so a 50,000-character result never lays out in full for three lines.
                    Text(entry.output.prefix(400)).lineLimit(3)
                    Text(entry.input.prefix(300)).lineLimit(2).foregroundStyle(.secondary)
                    Text(entry.metadata).font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.title), \(entry.appName)")
        .accessibilityValue(String(entry.output.prefix(400)))
        .accessibilityHint("Shows the details")
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
    /// "Fix grammar · Mail · 5 minutes ago · High · 1.8 s"; older entries have no level or duration; shortened ones say so.
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
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(alignment: .top) {
                        Text(entry.input)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CopyButton(title: "Copy Original", text: entry.input)
                    }
                    if entry.isShortened {
                        Label("Only the start was saved.", systemImage: "info.circle").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Original")
                }
                Section {
                    HStack(alignment: .top) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        CopyButton(title: "Copy Result", text: entry.output)
                    }
                    // Older entries kept only the start of the original: a diff against it would mark nearly everything.
                    Toggle("Show Changes", isOn: $showChanges).toggleStyle(.switch).disabled(entry.isShortened)
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
                Button("Delete", role: .destructive) {
                    delete()
                    dismiss()
                }
                .foregroundStyle(.red)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 600)
    }
}

/// A borderless copy icon at the end of a text row; shows a checkmark for a moment after copying.
private struct CopyButton: View {
    let title: String
    let text: String
    @State private var copied = false

    var body: some View {
        Button(title, systemImage: copied ? "checkmark" : "doc.on.doc") {
            HistoryEntry.copy(text)
            copied = true
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

// MARK: Usage

/// Totals from usage.json for the chosen period: today or the last 7, 30 or 90 days.
private struct UsageSection: View {
    let usage: Usage
    /// The period in days; 1 is today.
    @State private var days = 30

    var body: some View {
        let total = usage.total(days: days)
        let tokens = total.inputTokens + total.outputTokens
        let price = total.costUSD.formatted(.currency(code: "USD"))
        Section {
            Picker("Period", selection: $days) {
                ForEach([(1, "Today"), (7, "7 Days"), (30, "30 Days"), (90, "90 Days")], id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            HStack(alignment: .top) {
                StatCell(label: "Runs", value: total.runs.formatted(), spoken: total.runs.formatted())
                // Compact on screen ("1.2K" in English, like the rest of the UI); VoiceOver reads the full count.
                StatCell(label: "Tokens", value: tokens.formatted(.number.notation(.compactName).locale(HistoryEntry.english)),
                         spoken: tokens.formatted())
                StatCell(label: "Price", value: price, spoken: price)
            }
            .padding(.vertical, 4)
        } header: {
            SectionTitle("Usage")
        } footer: {
            Text("Price is the Claude Code list price. ChatGPT and custom API runs count tokens only.")
                .foregroundStyle(.secondary)
        }
    }
}

/// One figure of the usage row: a secondary label over a large value.
private struct StatCell: View {
    let label: String
    let value: String
    let spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
    }
}
