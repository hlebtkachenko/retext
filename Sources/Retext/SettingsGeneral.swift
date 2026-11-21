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
            Section("Startup") {
                IconRow(symbol: "power", tint: .green, title: "Open at Login",
                        subtitle: loginStatus == .requiresApproval ? "Waiting for approval in System Settings → General → Login Items." : nil) {
                    Toggle("Open at Login", isOn: Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                                                          set: { setOpenAtLogin($0) }))
                }
                IconRow(symbol: "menubar.rectangle", tint: .blue, title: "Show in Menu Bar",
                        subtitle: "When off, shortcuts keep working; open Retext from Spotlight or Finder to get to Settings.") {
                    Toggle("Show in Menu Bar", isOn: $state.settings.showMenuBarIcon)
                }
            }
            Section {
                ShortcutField()
            } footer: {
                Text("If another app uses ⌥Space, pick another shortcut or record your own. macOS may use ⌃⌥Space to switch input sources; you can turn that off in Keyboard Shortcuts.")
                    .foregroundStyle(.secondary)
            }
            Section("Preview") {
                IconRow(symbol: "eye", tint: .orange, title: "Preview Before Replacing",
                        subtitle: "Shows the result with the changes marked, so you can replace, copy or discard it. Text that can't be edited is copied either way.") {
                    Toggle("Preview Before Replacing", isOn: $state.settings.previewBeforeReplace)
                }
                PreviewSample()
            }
            Section("Backup") {
                IconRow(symbol: "externaldrive.fill", tint: .teal, title: "Back up your actions, styles and protected words",
                        subtitle: "Saves every setting except the API key to one file. History, usage and how much history is kept stay as they are on import and reset; an import also keeps this Mac's Claude Code and Codex paths and API server.")
                HStack {
                    Spacer()
                    Button("Export…", action: export)
                    Button("Import…", action: chooseImport)
                }
            }
            Section("Advanced") {
                IconRow(symbol: "bolt.horizontal.fill", tint: .purple, title: "Improve Electron App Support",
                        subtitle: "Asks every app you switch to for its accessibility tree, so ⌥1…⌥9 work in Electron apps (Slack, VS Code) right away.") {
                    Toggle("Improve Electron App Support", isOn: $state.settings.electronSupport)
                }
            }
            Section {
                IconRow(symbol: "arrow.counterclockwise", tint: .red, title: "Reset All Settings",
                        subtitle: "Every setting goes back to its default; history and usage are kept.") {
                    Button("Reset…", role: .destructive) { confirmReset = true }
                        .foregroundStyle(.red)
                        .accessibilityLabel("Reset All Settings")
                        // Here, not on the Form, so only this dialog is critical.
                        .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmReset) {
                            Button("Reset All Settings", role: .destructive) { replaceSettings(with: RetextSettings()) }
                            // Cancel is the default button, so Return never resets.
                            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
                        } message: {
                            Text("Actions, per-app styles, Protected Words, the AI provider and every other setting go back to the defaults. History and usage are kept. Export your settings first to keep a copy.")
                        }
                        .dialogSeverity(.critical)
                }
            }
        }
        // `general reset` shows the Reset row behind its dialog.
        .defaultScrollAnchor(SettingsView.demoExtra == "reset" ? .bottom : nil)
        // Every toggle sits in an IconRow, which shows its title.
        .toggleStyle(.switch)
        .labelsHidden()
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
            Text("Your current actions, per-app styles, Protected Words and other settings are replaced.")
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

/// "Preview before replacing" shown with the real bar on sample text; decorative, the row above describes it.
private struct PreviewSample: View {
    @StateObject private var model: PopupModel = {
        let model = PopupModel()
        model.phase = .preview(TextDiff.words(old: "Thanks for you're message, I will sent the files tomorow.",
                                              new: "Thanks for your message, I will send the files tomorrow."))
        return model
    }()

    var body: some View {
        PopupView(model: model, pick: { _ in }, choose: { _ in })
            .fixedSize()
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
