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

/// Menu items for running apps, then the other installed ones, each with its icon.
@MainActor
private func appItems(running: [AppInfo], installed: [AppInfo], pick: @escaping @MainActor (String) -> Void) -> [PullDownItem] {
    func items(_ apps: [AppInfo]) -> [PullDownItem] {
        apps.map { app in .action(app.name, image: AppIcons.icon(path: app.path)) { pick(app.bundleID) } }
    }
    let others = installed.filter { app in !running.contains { $0.bundleID == app.bundleID } }
    return [.header("Running")] + items(running) + [.separator, .header("Installed")] + items(others)
}

struct StylesPane: View {
    @Binding var styles: [AppStyle]
    @State private var running: [AppInfo] = []
    @State private var installed: [AppInfo] = []

    var body: some View {
        Form {
            PageDescription(.styles)
            ForEach($styles) { $style in
                Section { row($style) }
            }
            Section {
                HStack {
                    PullDownButton("Add App Style", systemImage: "plus", items: appItems(running: running, installed: installed) {
                        styles.append(AppStyle(bundleID: $0, style: ""))
                    })
                    .fixedSize()
                    Spacer()
                }
            } footer: {
                if styles.isEmpty {
                    Text("No app styles yet.").foregroundStyle(.secondary)
                }
            }
        }
        .task {
            running = AppInfo.running()
            installed = await Task.detached { AppInfo.installed() }.value
        }
    }

    private func row(_ style: Binding<AppStyle>) -> some View {
        let id = style.wrappedValue.id, bundleID = style.wrappedValue.bundleID
        let path = AppIcons.path(bundleID)
        let name = appName(bundleID, path: path)
        let remove = { styles.removeAll { $0.id == id } }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Group {
                    if let icon = AppIcons.icon(path: path) {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "app.dashed").font(.title2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(name).font(.headline)
                    Text(bundleID.isEmpty ? "No app chosen" : bundleID)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                PullDownButton("Change App", systemImage: "arrow.left.arrow.right",
                               items: appItems(running: running, installed: installed) { style.wrappedValue.bundleID = $0 })
                .fixedSize()
                Button("Remove \(name)", systemImage: "minus.circle", action: remove)
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .help("Remove")
            }
            TextField("Style for \(name)", text: style.style,
                      prompt: Text("e.g. casual and short, no greetings"), axis: .vertical)
                .lineLimit(2...5)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
        .contextMenu { Button("Remove", systemImage: "trash", role: .destructive, action: remove) }
    }

    private func appName(_ bundleID: String, path: String?) -> String {
        guard let path else { return bundleID.isEmpty ? "New app" : bundleID }
        return FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }
}
