import AppKit
import RetextCore
import SwiftUI

/// The first pane: what this build is, whether it can work, updates and links.
struct OverviewPane: View {
    @ObservedObject private var state = AppState.shared

    private static let version: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let short = info["CFBundleShortVersionString"] as? String else { return "Development build" }
        return (info["CFBundleVersion"] as? String).map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }()

    var body: some View {
        let page = Identity.pageURL(repository: UpdateChecker.repository)
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Retext").font(.title2.bold())
                        Text(Self.version).foregroundStyle(.secondary).textSelection(.enabled)
                        Text("Fixes, rewrites or translates the text you select in any app, in place.")
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            Section("Status") {
                AccessibilityRow()
                ProviderRow()
                Button("Show Welcome…") { WelcomeWindow.shared.show() }
            }
            Section {
                Toggle("Check for updates automatically", isOn: $state.settings.checkForUpdates)
                HStack {
                    Button("Check Now") { state.checkForUpdatesNow() }.disabled(state.checkingForUpdates)
                    if state.checkingForUpdates { ProgressView().controlSize(.small) }
                    if let result = state.updateCheckResult { ResultView(result: result) }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("At most once a day, at launch and when the Mac wakes, Retext asks GitHub for the latest release and shows \"Update available\" in the menu when there is a newer one. Check Now asks right away. Nothing is downloaded automatically. Apart from the custom API, when you choose it, this is the only network request Retext makes itself.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Link(destination: page) { Label("GitHub Repository", systemImage: "chevron.left.forwardslash.chevron.right") }
                Link(destination: page.appending(path: "blob/HEAD/CHANGELOG.md")) { Label("Changelog", systemImage: "doc.text") }
                Link(destination: page.appending(path: "issues/new")) { Label("Report an Issue", systemImage: "exclamationmark.bubble") }
            } header: {
                Text("Links")
            } footer: {
                Text("Not affiliated with Anthropic or OpenAI. Claude and Claude Code are trademarks of Anthropic; ChatGPT and Codex are trademarks of OpenAI.").foregroundStyle(.secondary)
            }
        }
        .onAppear {
            // `--demo settings overview update`: shows a found release without asking GitHub.
            if SettingsView.demoExtra == "update" { state.updateCheckResult = .available(Release(tag_name: "v9.9.9", html_url: page.appending(path: "releases").absoluteString)) }
        }
    }

    private struct ResultView: View {
        let result: UpdateCheckResult

        var body: some View {
            switch result {
            case .upToDate(let version):
                Label("Retext \(version) is the latest version.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .available(let release):
                Label("Retext \(release.version) is available.", systemImage: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                // Only a GitHub page is ever opened.
                if release.html_url.hasPrefix("https://github.com/"), let url = URL(string: release.html_url) {
                    Button("Open Release Page") { NSWorkspace.shared.open(url) }
                }
            case .failed(let reason):
                Label("Couldn't check: \(reason)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
    }
}
