import AppKit
import RetextCore
import SwiftUI

// MARK: Per-App Styles

/// An app the style picker offers; only Sendable values, so the scan can run off the main thread.
private struct AppInfo: Hashable, Sendable {
    let bundleID: String, name: String, path: String

    /// Apps in /Applications, ~/Applications and /System/Applications (top level), one per bundle id.
    static func installed() -> [AppInfo] {
        let folders = ["/Applications", NSString(string: "~/Applications").expandingTildeInPath, "/System/Applications"]
        var seen = Set<String>()
        return folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".app") }.map { "\(folder)/\($0)" }
        }
        .compactMap { path in
            guard let id = Bundle(path: path)?.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return AppInfo(bundleID: id, name: FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""), path: path)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @MainActor static func running() -> [AppInfo] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap { app in
            guard let id = app.bundleIdentifier, let url = app.bundleURL, id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return AppInfo(bundleID: id, name: app.localizedName ?? id, path: url.path)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

@MainActor
private enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    /// The app's icon at menu size, or nil when the bundle id isn't installed.
    static func icon(path: String?) -> NSImage? {
        guard let path else { return nil }
        if let icon = cache[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        cache[path] = icon
        return icon
    }

    static func path(_ bundleID: String) -> String? {
        bundleID.isEmpty ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
    }
}

/// A menu of running apps, then the other installed ones, each with its icon.
private struct AppMenu: View {
    let title: String, systemImage: String
    let running: [AppInfo], installed: [AppInfo]
    let pick: (String) -> Void

    var body: some View {
        Menu(title, systemImage: systemImage) {
            Section("Running") { items(running) }
            Section("Installed") { items(installed.filter { app in !running.contains { $0.bundleID == app.bundleID } }) }
        }
        .fixedSize()
    }

    private func items(_ apps: [AppInfo]) -> some View {
        ForEach(apps, id: \.bundleID) { app in
            Button { pick(app.bundleID) } label: {
                Label {
                    Text(app.name)
                } icon: {
                    if let icon = AppIcons.icon(path: app.path) { Image(nsImage: icon) }
                }
            }
        }
    }
}

struct StylesPane: View {
    @Binding var styles: [AppStyle]
    @State private var running: [AppInfo] = []
    @State private var installed: [AppInfo] = []

    var body: some View {
        Form {
            Section {
                ForEach($styles) { $style in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            let path = AppIcons.path(style.bundleID)
                            if let icon = AppIcons.icon(path: path) {
                                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "app.dashed").font(.title2).frame(width: 24, height: 24).foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading) {
                                Text(appName(style.bundleID, path: path)).font(.headline)
                                Text(style.bundleID.isEmpty ? "No app chosen" : style.bundleID)
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer()
                            AppMenu(title: "Change App", systemImage: "arrow.left.arrow.right", running: running, installed: installed) {
                                style.bundleID = $0
                            }
                            Button("Remove", systemImage: "minus.circle") { styles.removeAll { $0.id == style.id } }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                        TextField("Style", text: $style.style, prompt: Text("e.g. casual chat"), axis: .vertical)
                            .lineLimit(1...4)
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A style is added to the prompt when the text is selected in that app.").foregroundStyle(.secondary)
                    HStack {
                        AppMenu(title: "Add App Style", systemImage: "plus", running: running, installed: installed) {
                            styles.append(AppStyle(bundleID: $0, style: ""))
                        }
                        Spacer()
                    }
                }
            }
        }
        .task {
            running = AppInfo.running()
            installed = await Task.detached { AppInfo.installed() }.value
        }
    }

    private func appName(_ bundleID: String, path: String?) -> String {
        guard let path else { return bundleID.isEmpty ? "New app" : bundleID }
        return FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }
}
