import AppKit
import RetextCore
import SwiftUI

/// Settings; see `AppWindows` for the activation policy while it is open.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private(set) var window: NSWindow?

    /// With a pane, opens on it: the sidebar selection lives in `SettingsNavigation`, so the content is never rebuilt.
    /// The window has a unified toolbar and takes its title and toolbar items from SwiftUI (navigationTitle).
    func show(_ pane: SettingsView.Pane? = nil) {
        if let pane { SettingsNavigation.shared.go(to: pane) }
        if window == nil {
            let host = NSHostingController(rootView: SettingsView())
            host.sceneBridgingOptions = [.title, .toolbars]
            // The window keeps the size set here instead of following the content's ideal size.
            host.sizingOptions = []
            // The toolbar goes on before the content: with .toolbars bridging, SwiftUI fills the window's toolbar with the
            // view's toolbar items when the hosting controller is attached, and a toolbar set afterwards replaces them.
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: true)
            w.toolbar = NSToolbar(identifier: "settings")
            w.toolbarStyle = .unified
            w.contentViewController = host
            // A demo window is taller, so one screenshot shows more of a pane.
            w.setContentSize(NSSize(width: 780, height: AppWindows.isDemo ? 900 : 620))
            w.contentMinSize = NSSize(width: 680, height: 460)
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        // navigationTitle leaves "Untitled" until the selection changes, so the title is also set here.
        window?.title = SettingsNavigation.shared.pane.rawValue
        AppWindows.bringForward(window)
    }

    func windowWillClose(_ notification: Notification) {
        // A reopened window starts a fresh visit, with nothing to go Back or Forward to.
        SettingsNavigation.shared.clearHistory()
        if let window { AppWindows.closing(window) }
    }
}

/// The selected Settings pane, shared so the menu, Check for Updates… and a second launch can switch it, with the
/// Back and Forward history of the toolbar's navigation buttons.
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    /// Set it directly only to open a pane without history (a demo); everything else uses `go(to:)`.
    @Published var pane = SettingsView.Pane.about
    @Published private(set) var backStack: [SettingsView.Pane] = []
    @Published private(set) var forwardStack: [SettingsView.Pane] = []

    /// Opens `pane` and remembers the current one for Back; a new visit clears Forward, as in a browser.
    func go(to pane: SettingsView.Pane) {
        guard pane != self.pane else { return }
        backStack.append(self.pane)
        forwardStack.removeAll()
        self.pane = pane
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(pane)
        pane = previous
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(pane)
        pane = next
    }

    /// Forgets Back and Forward and keeps the current pane.
    func clearHistory() {
        backStack.removeAll()
        forwardStack.removeAll()
    }
}

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case about = "About", general = "General", actions = "Actions", styles = "Per-App Styles", words = "Protected Words", ai = "AI", history = "History"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .about: "info.circle"
            case .general: "gearshape.fill"
            case .actions: "list.bullet"
            case .styles: "macwindow"
            case .words: "lock.fill"
            case .ai: "sparkles"
            case .history: "clock.arrow.circlepath"
            }
        }

        /// The sidebar tile's color.
        var tint: Color {
            switch self {
            case .about: .blue
            case .general: .gray
            case .actions: .blue
            case .styles: .purple
            case .words: .orange
            case .ai: .pink
            case .history: .green
            }
        }

        /// Earlier pane names, so `--demo settings overview` and older notes keep working.
        private static let aliases: [String: Pane] = ["overview": .about, "engine": .ai, "usage": .history, "app": .styles]

        /// `--demo settings <name>`: the case name (styles, words), an alias, or the start of the title (per, protected).
        init?(demoName name: String) {
            let name = name.lowercased()
            guard !name.isEmpty, let pane = Self.allCases.first(where: { "\($0)" == name }) ?? Self.aliases[name]
                    ?? Self.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(name) }) else { return nil }
            self = pane
        }
    }

    @ObservedObject private var state = AppState.shared
    @ObservedObject private var navigation = SettingsNavigation.shared
    /// `--demo settings <pane> <extra>`: the word after the pane opens a dialog or expands a row, for screenshots.
    static let demoExtra: String? = CommandLine.arguments.firstIndex(of: "--demo").flatMap { i in
        CommandLine.arguments.dropFirst(i + 1).first == "settings" ? CommandLine.arguments.dropFirst(i + 3).first : nil
    }

    var body: some View {
        let selection = Binding<Pane?>(get: { navigation.pane }, set: { if let pane = $0 { navigation.go(to: pane) } })
        NavigationSplitView {
            List(selection: selection) {
                Section {
                    AboutSidebarRow().tag(Pane.about)
                }
                Section {
                    ForEach(Pane.allCases.filter { $0 != .about }) { pane in
                        Label {
                            Text(pane.rawValue)
                        } icon: {
                            SidebarTile(symbol: pane.symbol, tint: pane.tint)
                        }
                        .tag(pane)
                    }
                }
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 220)
        } detail: {
            Group {
                switch navigation.pane {
                case .about: AboutPane()
                case .general: GeneralPane()
                case .actions: ActionsPane(actions: $state.settings.actions)
                case .styles: StylesPane(styles: $state.settings.appStyles)
                case .words: WordsPane(settings: $state.settings)
                case .ai: EnginePane()
                case .history: HistoryPane()
                }
            }
            .formStyle(.grouped)
            // A hard edge draws a line between the toolbar and the pane, as in NotchPop.
            .scrollEdgeEffectStyle(.hard, for: .top)
            .navigationTitle(navigation.pane.rawValue)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { navigation.goBack() } label: { Label("Back", systemImage: "chevron.backward") }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(navigation.backStack.isEmpty)
                    .help("Back")
                Button { navigation.goForward() } label: { Label("Forward", systemImage: "chevron.forward") }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(navigation.forwardStack.isEmpty)
                    .help("Forward")
            }
        }
        .onChange(of: navigation.pane) { _, pane in SettingsWindow.shared.window?.title = pane.rawValue }
    }
}

/// The sidebar's first row, like the account row of Raycast or NotchPop: the app icon, its name and "About"
/// (or "Update Available"); it opens About.
private struct AboutSidebarRow: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Retext").font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Retext, \(subtitle)")
    }

    private var subtitle: String { state.update != nil ? "Update Available" : "About" }
}

/// A white symbol on a tinted rounded square, the sidebar's icon style (as in System Settings).
struct SidebarTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}
