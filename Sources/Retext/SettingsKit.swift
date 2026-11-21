import RetextCore
import SwiftUI

// Shared building blocks of the Settings panes.

/// A row with a symbol in its tint on a neutral rounded square, a title, an optional secondary subtitle and trailing content
/// (a toggle, a picker, a button).
struct IconRow<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String?
    let trailing: Trailing

    init(symbol: String, tint: Color, title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension IconRow where Trailing == EmptyView {
    init(symbol: String, tint: Color, title: String, subtitle: String? = nil) {
        self.init(symbol: symbol, tint: tint, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The row's symbol in its tint on a neutral rounded square with a hairline border; decorative for VoiceOver.
private struct IconTile: View {
    let symbol: String
    let tint: Color
    private let size: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(.quaternary, in: shape)
            .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// The first section of a pane: what the page is for, in plain secondary text on the window background.
/// Put it first in the pane's `Form`: `PageDescription(.actions)`, or `PageDescription("Any text.")`.
struct PageDescription: View {
    let text: String

    init(_ pane: SettingsView.Pane) { text = pane.summary }
    init(_ text: String) { self.text = text }

    var body: some View {
        Section {
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Color.clear)
    }
}

extension SettingsView.Pane {
    /// The sentence `PageDescription` shows at the top of the pane.
    var summary: String {
        switch self {
        case .about: "Fixes, rewrites or translates the text you select in any app, in place."
        case .general: "How Retext starts, opens and shows its results."
        case .actions: "Saved instructions you run from the bar or with ⌥1…⌥9."
        case .styles: "A style tells every action how to write in that app."
        case .words: "Names and terms Retext keeps as written, even in translations."
        case .ai: "The AI that rewrites your text. Higher levels give better results and take longer."
        case .history: "Your past results and how much Retext has used."
        }
    }
}

extension View {
    /// A pop-up button with a border, the chosen value and up-down chevrons, like a pop-up in System Settings.
    /// Put it on a `Picker` in a grouped Form, usually with `.labelsHidden()` when the row shows the title:
    /// `Picker("Provider", selection: $provider) { ... }.labelsHidden().borderedPopUp()`.
    func borderedPopUp() -> some View {
        pickerStyle(.menu).buttonStyle(.bordered).fixedSize()
    }

    /// A pull-down button with a border, the label and one down chevron, for a `Menu` of commands
    /// (Add App Style, Presets): `Menu("Presets") { ... }.borderedPullDown()`.
    func borderedPullDown() -> some View {
        menuStyle(.button).buttonStyle(.bordered).menuIndicator(.visible).fixedSize()
    }
}

/// Runs one tiny request at Medium with the active provider; counted in usage like any other call.
struct TestButton: View {
    let title: String
    /// Extra checks before the request (nil = go on) and a description of what was tested after it.
    var precheck: () async -> ClaudeFailure? = { nil }
    var success: () async -> String = { "Works" }
    @ObservedObject private var state = AppState.shared
    @State private var testing = false
    @State private var result: (ok: Bool, text: String)?

    var body: some View {
        HStack {
            Button(title, action: test).disabled(testing).help("Sends one tiny request at Medium.")
            if testing { ProgressView().controlSize(.small) }
            if let result {
                Label(result.text, systemImage: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(result.ok ? Color.green : .orange)
                    .textSelection(.enabled)
            }
        }
    }

    private func test() {
        let settings = state.settings
        testing = true
        result = nil
        Task {
            defer { testing = false }
            let m = settings.model(for: .medium)
            let job = Job(title: "Test", provider: settings.provider, model: m.model, effort: m.effort, system: "Reply with OK.")
            do {
                if let failure = await precheck() { throw failure }
                let output = try await ProviderRunner.run(job, text: "ok", settings: settings, timeout: Level.medium.timeout)
                state.usage.recordCall(model: job.model, output: output)
                try output.checkComplete()
                result = (true, await success())
            } catch {
                let failure = error as? ClaudeFailure ?? .other("")
                result = (false, failure.message(for: settings.provider))
            }
            state.checkProvider()
        }
    }
}
