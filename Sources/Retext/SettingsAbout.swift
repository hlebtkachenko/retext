import AppKit
import RetextCore
import SwiftUI

/// This build's version, from Info.plist; nil in a `swift build` binary.
enum AppVersion {
    static let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    static let full: String = {
        guard let short else { return "Development build" }
        return (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }()
}

/// The first pane (the sidebar's Retext row): what this build is, whether it can work, onboarding, updates and links.
struct AboutPane: View {
    @ObservedObject private var state = AppState.shared
    /// `RetextWebsite` in Info.plist.
    private static let website = (Bundle.main.object(forInfoDictionaryKey: "RetextWebsite") as? String).flatMap(URL.init(string:))

    var body: some View {
        let page = Identity.pageURL(repository: UpdateChecker.repository)
        Form {
            Section {
                hero
            }
            .listRowBackground(Color.clear)
            Section {
                GetStartedCard()
            }
            Section("Status") {
                AccessibilityRow()
                ProviderRow()
            }
            Section("Updates") {
                if let update = state.update { UpdateCard(release: update) }
                IconRow(symbol: "arrow.triangle.2.circlepath", tint: .blue, title: "Check for Updates Automatically") {
                    Toggle("Check for Updates Automatically", isOn: $state.settings.checkForUpdates).labelsHidden().toggleStyle(.switch)
                }
                .help("Asks GitHub at most once a day. Nothing is downloaded.")
                IconRow(symbol: "checkmark.seal.fill", tint: .green, title: lastCheckedText) {
                    if state.checkingForUpdates { ProgressView().controlSize(.small) }
                    Button("Check Now") { state.checkForUpdatesNow() }.disabled(state.checkingForUpdates)
                }
                if let result = state.updateCheckResult { ResultLine(result: result) }
            }
            Section {
                if let website = Self.website {
                    LinkRow(title: "Website", destination: website) { Image(systemName: "globe") }
                }
                LinkRow(title: "GitHub Repository", destination: page) {
                    GitHubMark().fill(.primary).frame(width: 15, height: 15).accessibilityLabel("GitHub")
                }
                LinkRow(title: "Changelog", destination: page.appending(path: "blob/HEAD/CHANGELOG.md")) { Image(systemName: "doc.text") }
                LinkRow(title: "Report an Issue", destination: page.appending(path: "issues/new")) { Image(systemName: "exclamationmark.bubble") }
            } header: {
                Text("Links")
            } footer: {
                Text("Not affiliated with Anthropic or OpenAI. Claude and Claude Code are trademarks of Anthropic; ChatGPT and Codex are trademarks of OpenAI.")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Retext").font(.largeTitle.bold())
            Text(AppVersion.full).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Fixes, rewrites or translates the text you select in any app, in place.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var lastCheckedText: String {
        guard let date = UpdateChecker.lastChecked else { return "Not checked yet" }
        return "Last checked \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    /// The last manual check's answer; an available release is shown by `UpdateCard` instead.
    private struct ResultLine: View {
        let result: UpdateCheckResult

        var body: some View {
            switch result {
            case .upToDate:
                Label("You're on the latest version.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .available:
                EmptyView()
            case .failed(let reason):
                Label("Couldn't check: \(reason)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
    }
}

/// A found release: its version, the release page (only ever a GitHub page) and how to update a build from source.
private struct UpdateCard: View {
    let release: Release

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconRow(symbol: "arrow.down.circle.fill", tint: .accentColor, title: "Update Available (\(release.version))") {
                if release.html_url.hasPrefix("https://github.com/"), let url = URL(string: release.html_url) {
                    Button("Open Release Page") { NSWorkspace.shared.open(url) }.buttonStyle(.borderedProminent)
                }
            }
            Text("Built from source? In your Retext folder run \(Text("git pull && ./build.sh").font(.callout.monospaced())).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.leading, 34)
        }
        .padding(.vertical, 4)
    }
}

/// The Raycast "Watch Video" card, without a video: opens Onboarding.
private struct GetStartedCard: View {
    var body: some View {
        HStack(spacing: 14) {
            SidebarTile(symbol: "hand.wave.fill", tint: .accentColor, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Onboarding").font(.headline)
                Text("Grant access, pick your AI and try the shortcut.").foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Start") { OnboardingWindow.shared.show() }.controlSize(.large)
        }
        .padding(.vertical, 6)
    }
}

/// A link row: icon, title and the outward arrow, the whole row clickable.
private struct LinkRow<Icon: View>: View {
    let title: String
    let destination: URL
    @ViewBuilder let icon: Icon

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 10) {
                icon.frame(width: 20).foregroundStyle(.primary)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
