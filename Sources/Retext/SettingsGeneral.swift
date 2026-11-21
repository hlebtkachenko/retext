import AppKit
import RetextCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// MARK: General

struct GeneralPane: View {
    @ObservedObject private var state = AppState.shared
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var confirmReset = false
    @State private var pendingImport: RetextSettings?
    @State private var backupError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: { setOpenAtLogin($0) }))
            } footer: {
                if loginStatus == .requiresApproval {
                    Text("Waiting for approval in System Settings → General → Login Items.").foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Show in menu bar", isOn: $state.settings.showMenuBarIcon)
            } footer: {
                Text("Off: shortcuts keep working; open Retext again from Spotlight or Finder to get back to Settings.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ShortcutField()
            } footer: {
                Text("Choose ⌃⌥Space if another app uses ⌥Space; macOS may use ⌃⌥Space to switch input sources, which you can turn off in Keyboard Shortcuts.").foregroundStyle(.secondary)
            }
            Section {
                Toggle("Preview before replacing", isOn: $state.settings.previewBeforeReplace)
            } footer: {
                Text("Text that can't be edited is copied either way.")
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Export Settings…", action: export)
                    Button("Import Settings…", action: chooseImport)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("History and usage are not included and are kept on import and reset.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Improve Electron app support", isOn: $state.settings.electronSupport)
            } header: {
                Text("Advanced")
            } footer: {
                Text("Asks every app you switch to for its accessibility tree, so ⌥1…⌥9 work in Electron apps (Slack, VS Code) right away.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Reset All Settings to Defaults…", role: .destructive) { confirmReset = true }
                    .foregroundStyle(.red)
                    // Here, not on the Form, so only this dialog is critical.
                    .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmReset) {
                        Button("Reset All Settings", role: .destructive) { replaceSettings(with: RetextSettings()) }
                        // Cancel is the default button, so Return never resets.
                        Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
                    } message: {
                        Text("Actions, app styles, protected words, the provider and every other setting go back to the defaults. History and usage are kept. Export your settings first to keep a copy.")
                    }
                    .dialogSeverity(.critical)
            }
        }
        .onAppear {
            loginStatus = SMAppService.mainApp.status
            if SettingsView.demoExtra == "reset" { confirmReset = true }
        }
        .confirmationDialog("Replace all settings with the imported ones?",
                            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Replace Settings", role: .destructive) {
                // The Claude Code and Codex paths belong to this Mac, not to the exported file.
                if var pendingImport {
                    pendingImport.claudePath = state.settings.claudePath
                    pendingImport.codexPath = state.settings.codexPath
                    // The API key is saved for the current server: an imported file must not point it at another server.
                    pendingImport.custom.baseURL = state.settings.custom.baseURL
                    replaceSettings(with: pendingImport)
                }
                pendingImport = nil
            }
        } message: {
            Text("Your current actions, app styles, protected words and other settings are replaced.")
        }
        .alert(backupError ?? "", isPresented: Binding(get: { backupError != nil }, set: { if !$0 { backupError = nil } })) {}
    }

    /// Keeps `onboarded`, so the welcome window doesn't come back after an import or reset, and `historyRetention`,
    /// which goes with the history that is kept too.
    private func replaceSettings(with new: RetextSettings) {
        var new = new
        new.onboarded = state.settings.onboarded
        new.historyRetention = state.settings.historyRetention
        state.settings = new
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Retext Settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try state.settings.encoded().write(to: url, options: .atomic) } catch {
            backupError = "Couldn't export the settings: \(error.localizedDescription)"
        }
    }

    /// Decodes first, so a file that isn't Retext settings is rejected before anything is asked or replaced.
    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { pendingImport = try RetextSettings.imported(from: Data(contentsOf: url)) } catch {
            backupError = "\(url.lastPathComponent) isn't a Retext settings file."
        }
    }

    /// Registers or unregisters the login item, then shows what the system reports.
    private func setOpenAtLogin(_ on: Bool) {
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        loginStatus = SMAppService.mainApp.status
    }
}
