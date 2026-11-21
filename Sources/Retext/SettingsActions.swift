import AppKit
import RetextCore
import SwiftUI

/// The action list; clicking a row expands its editor right under it and collapses the others.
struct ActionsPane: View {
    @Binding var actions: [CustomAction]
    @State private var expanded: CustomAction.ID?
    @State private var confirmRestore = false

    var body: some View {
        Form {
            Section {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    let isExpanded = expanded == action.id
                    // A button, not a tap gesture, so the rows are reachable with the keyboard and VoiceOver.
                    Button { withAnimation(.snappy) { expanded = isExpanded ? nil : action.id } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .frame(width: 12)
                            Image(systemName: action.symbol).frame(width: 20).foregroundStyle(isExpanded ? Color.accentColor : .primary)
                            Text(action.title).fontWeight(isExpanded ? .semibold : .regular)
                            Spacer()
                            Text(action.kind.rawValue.capitalized).foregroundStyle(.secondary)
                            Text("⌥\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isExpanded ? .isSelected : [])
                    .accessibilityHint(isExpanded ? "Collapses the editor" : "Expands the editor")
                    if isExpanded {
                        ActionEditor(action: binding(action.id), position: index, count: actions.count,
                                     move: { move(action.id, by: $0) },
                                     delete: { actions.removeAll { $0.id == action.id }; expanded = nil })
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⌥1 to ⌥9 run the actions in list order.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Add Action", systemImage: "plus") {
                            let action = CustomAction(title: "New action", symbol: "sparkles", prompt: "", kind: .other)
                            actions.append(action)
                            expanded = action.id
                        }
                        .disabled(actions.count >= RetextSettings.maxActions)
                        Spacer()
                        Button("Restore Default Actions…", role: .destructive) { confirmRestore = true }
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .onAppear {
            switch SettingsView.demoExtra {
            case "expand", "icons": expanded = actions.first?.id
            case "restore": confirmRestore = true
            default: break
            }
        }
        .confirmationDialog("Restore the default actions?", isPresented: $confirmRestore) {
            Button("Restore Default Actions", role: .destructive) {
                actions = RetextSettings.defaultActions
                expanded = nil
            }
            // Cancel is the default button, so Return never restores.
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: {
            Text("Your actions are replaced by Fix grammar, English and a translation into your Mac's language. Edited prompts and added actions are lost.")
        }
        .dialogSeverity(.critical)
    }

    private func binding(_ id: CustomAction.ID) -> Binding<CustomAction> {
        Binding(get: { actions.first { $0.id == id } ?? CustomAction(title: "", symbol: "", prompt: "", kind: .other) },
                set: { new in if let i = actions.firstIndex(where: { $0.id == id }) { actions[i] = new } })
    }

    private func move(_ id: CustomAction.ID, by offset: Int) {
        guard let i = actions.firstIndex(where: { $0.id == id }), actions.indices.contains(i + offset) else { return }
        actions.swapAt(i, i + offset)
    }
}

/// The expanded action's fields, as form rows under its list row.
private struct ActionEditor: View {
    @Binding var action: CustomAction
    let position: Int, count: Int
    let move: (Int) -> Void
    let delete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        let defaultPrompt = RetextSettings.defaultPrompt(for: action)
        Group {
            TextField("Title", text: $action.title)
            LabeledContent("Icon") { IconPicker(symbol: $action.symbol) }
            Picker("Kind", selection: $action.kind) {
                Text("Grammar").tag(ActionKind.grammar)
                Text("Translate").tag(ActionKind.translate)
                Text("Other").tag(ActionKind.other)
            }
            .help("Grammar and Translate keep a one-line text on one line unless an app style applies, and a Grammar result much longer than the text is rejected. Other has no such checks.")
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                TextField("Prompt", text: $action.prompt, prompt: Text("What Retext should do with the selected text"), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(5...14)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                // One row when it fits, else one example per line.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { exampleButtons }
                    VStack(alignment: .leading, spacing: 6) { exampleButtons }
                }
            }
            HStack {
                Button("Move Up", systemImage: "arrow.up") { move(-1) }.disabled(position == 0)
                Button("Move Down", systemImage: "arrow.down") { move(1) }.disabled(position == count - 1)
                Spacer()
                Button("Reset Prompt") { if let defaultPrompt { action.prompt = defaultPrompt } }
                    .disabled(defaultPrompt == nil || defaultPrompt == action.prompt)
                    .help("Puts back the built-in prompt for Grammar, or for Translate into the language named in the title.")
                Button("Delete Action…", role: .destructive) { confirmDelete = true }
                    .foregroundStyle(.red)
            }
            // On this row, not the Group: a modifier on a Group applies to each of its rows.
            .confirmationDialog("Delete “\(action.title)”?", isPresented: $confirmDelete) {
                Button("Delete Action", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
            } message: {
                Text("Its prompt is lost, and the actions after it move up one shortcut.")
            }
        }
        .padding(.leading, 20)
    }

    private var exampleButtons: some View {
        ForEach(Self.examples, id: \.self) { example in
            Button(example) { insert(example) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .help("Use this prompt")
        }
    }

    private static let examples = ["Make it shorter and keep the meaning.", "Rewrite it more politely.", "Rewrite it in a formal business tone."]

    /// An empty prompt becomes the example; otherwise the example is added on a new line.
    private func insert(_ example: String) {
        let prompt = action.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        action.prompt = prompt.isEmpty ? example : prompt + "\n" + example
    }
}

/// A button showing the action's icon that opens a grid of symbols suited to text actions.
private struct IconPicker: View {
    @Binding var symbol: String
    @State private var picking = SettingsView.demoExtra == "icons"

    /// Each checked with NSImage(systemSymbolName:); all predate macOS 26.
    static let symbols = [
        "text.badge.checkmark", "globe", "character.bubble", "textformat", "text.quote",
        "text.alignleft", "scissors", "arrow.down.right.and.arrow.up.left", "arrow.up.left.and.arrow.down.right", "wand.and.stars",
        "sparkles", "face.smiling", "briefcase", "envelope", "bubble.left.and.text.bubble.right",
        "list.bullet", "checklist", "pencil", "lightbulb", "hand.thumbsup",
    ]

    /// Short names for VoiceOver and the tooltip instead of the SF Symbol names ("Shorten", not "arrow.down.right…").
    static let names = [
        "text.badge.checkmark": "Checked text", "globe": "Globe", "character.bubble": "Speech bubble with letter",
        "textformat": "Text format", "text.quote": "Quote", "text.alignleft": "Left-aligned text", "scissors": "Scissors",
        "arrow.down.right.and.arrow.up.left": "Shorten", "arrow.up.left.and.arrow.down.right": "Expand",
        "wand.and.stars": "Magic wand", "sparkles": "Sparkles", "face.smiling": "Smiling face", "briefcase": "Briefcase",
        "envelope": "Envelope", "bubble.left.and.text.bubble.right": "Conversation", "list.bullet": "Bulleted list",
        "checklist": "Checklist", "pencil": "Pencil", "lightbulb": "Light bulb", "hand.thumbsup": "Thumbs up",
    ]

    /// A symbol outside the list (a hand-edited settings.json) reads as its name with spaces for the dots.
    static func spokenName(_ symbol: String) -> String {
        names[symbol] ?? symbol.replacingOccurrences(of: ".", with: " ")
    }

    var body: some View {
        Button { picking.toggle() } label: {
            HStack(spacing: 6) {
                SymbolImage(name: symbol).frame(width: 20)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Icon: \(Self.spokenName(symbol))")
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            // A saved symbol outside the list stays offered, first, so the action keeps it until another is picked.
            let choices = (Self.symbols.contains(symbol) ? [] : [symbol]) + Self.symbols
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 5), spacing: 6) {
                ForEach(choices, id: \.self) { name in
                    let selected = name == symbol
                    Button { symbol = name; picking = false } label: {
                        SymbolImage(name: name)
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Self.spokenName(name))
                    .accessibilityLabel(Self.spokenName(name))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(12)
        }
    }
}

/// The SF Symbol, or a warning when no symbol has that name (a hand-edited settings.json).
private struct SymbolImage: View {
    let name: String

    var body: some View {
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                .help("No SF Symbol has this name")
        } else {
            Image(systemName: name)
        }
    }
}
