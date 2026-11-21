import AppKit
import RetextCore
import SwiftUI

/// Settings; see `AppWindows` for the activation policy while it is open.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private(set) var window: NSWindow?

    /// With a pane, opens on it (rebuilding the content, since the sidebar selection is view state). The title is set
    /// here, before SwiftUI's first update: navigationTitle renames the window when another pane is picked, but leaves
    /// "Untitled" when it opens on a pane other than Overview, and a title set from the view resets the pane's state.
    func show(_ pane: SettingsView.Pane? = nil) {
        if let pane {
            SettingsView.initialPane = pane
            if let window {
                let frame = window.frame
                window.contentViewController = NSHostingController(rootView: SettingsView())
                window.setFrame(frame, display: false)
                window.title = pane.rawValue
            }
        }
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = SettingsView.initialPane.rawValue
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 760, height: 620))
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        AppWindows.bringForward(window)
    }

    func windowWillClose(_ notification: Notification) {
        if let window { AppWindows.closing(window) }
    }
}

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case overview = "Overview", actions = "Actions", styles = "App styles", words = "Protected words", engine = "Engine", general = "General", usage = "Usage"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .overview: "info.circle"
            case .actions: "list.bullet"
            case .styles: "app.badge"
            case .words: "lock"
            case .engine: "cpu"
            case .general: "gearshape"
            case .usage: "chart.bar"
            }
        }
    }

    @ObservedObject private var state = AppState.shared
    static var initialPane = Pane.overview
    /// `--demo settings <pane> <extra>`: the word after the pane opens a dialog or expands a row, for screenshots.
    static let demoExtra: String? = CommandLine.arguments.firstIndex(of: "--demo").flatMap { i in
        CommandLine.arguments.dropFirst(i + 1).first == "settings" ? CommandLine.arguments.dropFirst(i + 3).first : nil
    }
    @State private var pane: Pane? = SettingsView.initialPane

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.rawValue, systemImage: pane.symbol)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch pane ?? .overview {
                case .overview: OverviewPane()
                case .actions: ActionsPane(actions: $state.settings.actions)
                case .styles: StylesPane(styles: $state.settings.appStyles)
                case .words: WordsPane(settings: $state.settings)
                case .engine: EnginePane()
                case .general: GeneralPane()
                case .usage: UsagePane(usage: state.usage)
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane ?? .overview).rawValue)
        }
    }
}
