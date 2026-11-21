import AppKit
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
    /// A fixed title column (one line): the trailing controls then start right after it and may fill the rest,
    /// so rows with the same width line up. Without it, the controls sit at the trailing edge.
    var titleWidth: CGFloat?
    let trailing: Trailing

    init(symbol: String, tint: Color, title: String, subtitle: String? = nil, titleWidth: CGFloat? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.titleWidth = titleWidth
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, tint: tint)
            if let titleWidth {
                Text(title).lineLimit(1).frame(width: titleWidth, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
            }
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
/// The one exception is About, which shows `Pane.about.summary` in its hero, under the app's name.
struct PageDescription: View {
    let text: String

    init(_ pane: SettingsView.Pane) { text = pane.summary }
    init(_ text: String) { self.text = text }

    var body: some View {
        // A header with no rows: a row, even with a clear background, sits on the section's tile.
        Section {
        } header: {
            Text(text)
                .font(.body)
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
        }
    }
}

/// A section title in every pane's own weight: after `PageDescription`'s header-only section a plain `Section("…")`
/// title is drawn small and secondary, so every pane titles its sections with this instead.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.headline).foregroundStyle(.primary)
    }
}

extension SettingsView.Pane {
    /// The sentence `PageDescription` shows at the top of the pane (About shows it in its hero instead).
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

/// A bordered pop-up button showing the chosen value and up-down chevrons, as in System Settings.
/// A SwiftUI `Picker` in a grouped Form draws without a border whatever its style, so this wraps `NSPopUpButton`.
/// Use it as a row's trailing control: `PopUpPicker("Provider", selection: $provider, options: Provider.allCases) { $0.title }.fixedSize()`.
/// `title` is the VoiceOver label; the row shows the visible title. With `width`, the bordered button is exactly that wide
/// (`.fixed`) or as wide as offered (`.fill`), and a long title truncates, so pop-ups in a column line up; without it,
/// it takes its title's width.
struct PopUpPicker<Value: Hashable>: NSViewRepresentable {
    enum Width { case fixed(CGFloat), fill }

    let title: String
    @Binding var selection: Value
    let options: [Value]
    var width: Width?
    let label: (Value) -> String

    init(_ title: String, selection: Binding<Value>, options: [Value], width: Width? = nil, label: @escaping (Value) -> String) {
        self.title = title
        _selection = selection
        self.options = options
        self.width = width
        self.label = label
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        // The default push style draws no border on macOS 26; this one keeps the bordered rounded rectangle.
        button.bezelStyle = .flexiblePush
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        // A fixed width must win over the title's width, or SwiftUI centers the button at its intrinsic size.
        let priority: NSLayoutConstraint.Priority = width == nil ? .required : .defaultLow
        button.setContentHuggingPriority(priority, for: .horizontal)
        button.setContentCompressionResistancePriority(priority, for: .horizontal)
        if width != nil { button.cell?.lineBreakMode = .byTruncatingTail }
        return button
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        switch width {
        case nil: return nil
        case .fixed(let fixed): return CGSize(width: fixed, height: intrinsic.height)
        case .fill:
            // An unspecified or infinite proposal (an ideal-size query) gets the title's width.
            let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? intrinsic.width
            return CGSize(width: offered, height: intrinsic.height)
        }
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onChoose = { index in
            if options.indices.contains(index) { selection = options[index] }
        }
        let titles = options.map(label)
        if button.itemTitles != titles {
            button.removeAllItems()
            // Titles that repeat would collapse into one item with `addItems(withTitles:)`.
            for title in titles { button.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "") }
        }
        button.selectItem(at: options.firstIndex(of: selection) ?? -1)
        button.setAccessibilityLabel(title)
        button.isEnabled = context.environment.isEnabled
    }

    @MainActor final class Coordinator: NSObject {
        var onChoose: (Int) -> Void = { _ in }
        @objc func choose(_ sender: NSPopUpButton) { onChoose(sender.indexOfSelectedItem) }
    }
}

/// One entry of a `PullDownButton` menu.
enum PullDownItem {
    case action(String, image: NSImage? = nil, enabled: Bool = true, perform: @MainActor () -> Void)
    case submenu(String, image: NSImage? = nil, [PullDownItem])
    /// A section title (not clickable).
    case header(String)
    case separator
}

/// A bordered pull-down button: the title, an optional symbol and one down chevron, opening a menu of commands.
/// A SwiftUI `Menu` in a grouped Form draws without a border whatever its style, so this wraps `NSPopUpButton`.
/// `PullDownButton("Presets", items: { [.action("OpenAI") { ... }, .separator, .header("Local"), ...] }).fixedSize()`;
/// `items` runs each time the menu opens, so it reads the state of that moment and a long list costs nothing until then.
/// `accessibilityLabel` replaces the title for VoiceOver, where one title repeats on several rows.
struct PullDownButton: NSViewRepresentable {
    let title: String
    var systemImage: String?
    var accessibilityLabel: String?
    let items: () -> [PullDownItem]

    init(_ title: String, systemImage: String? = nil, accessibilityLabel: String? = nil, items: @escaping () -> [PullDownItem]) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.items = items
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .flexiblePush
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        let menu = NSMenu()
        menu.autoenablesItems = false
        // A pull-down shows its first item as the button's face; the rest is added when the menu opens.
        let face = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        face.image = systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        context.coordinator.faceSymbol = systemImage
        menu.addItem(face)
        menu.delegate = context.coordinator
        button.menu = menu
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.items = items
        if let face = button.menu?.items.first {
            if face.title != title { face.title = title }
            if context.coordinator.faceSymbol != systemImage {
                context.coordinator.faceSymbol = systemImage
                face.image = systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            }
        }
        if button.accessibilityLabel() != (accessibilityLabel ?? title) { button.setAccessibilityLabel(accessibilityLabel ?? title) }
        button.isEnabled = context.environment.isEnabled
    }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        var items: () -> [PullDownItem] = { [] }
        /// The symbol on the face now, so an update sets the image only when it changes.
        var faceSymbol: String?
        private var actions: [@MainActor () -> Void] = []

        /// Rebuilds everything after the face item from the current `items`.
        func menuNeedsUpdate(_ menu: NSMenu) {
            while menu.items.count > 1 { menu.removeItem(at: 1) }
            actions = []
            add(items(), to: menu)
        }

        private func add(_ items: [PullDownItem], to menu: NSMenu) {
            for item in items {
                switch item {
                case let .action(title, image, enabled, perform):
                    let entry = NSMenuItem(title: title, action: enabled ? #selector(run(_:)) : nil, keyEquivalent: "")
                    entry.target = self
                    entry.image = image
                    entry.isEnabled = enabled
                    entry.tag = actions.count
                    actions.append(perform)
                    menu.addItem(entry)
                case let .submenu(title, image, children):
                    let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    entry.image = image
                    let sub = NSMenu(title: title)
                    sub.autoenablesItems = false
                    add(children, to: sub)
                    entry.submenu = sub
                    menu.addItem(entry)
                case let .header(title):
                    menu.addItem(.sectionHeader(title: title))
                case .separator:
                    menu.addItem(.separator())
                }
            }
        }

        @objc private func run(_ sender: NSMenuItem) {
            if actions.indices.contains(sender.tag) { actions[sender.tag]() }
        }
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
