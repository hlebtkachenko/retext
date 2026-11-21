import AppKit
import RetextCore
import SwiftUI
import UniformTypeIdentifiers

/// The action list: drag a row (or use its context menu or VoiceOver actions) to reorder, click it to edit in a sheet.
/// Dragging moves the row live as it passes over the others; `onMove` does nothing in a grouped Form on macOS.
struct ActionsPane: View {
    @Binding var actions: [CustomAction]
    /// The action being dragged; nil when no drag is in progress.
    @State private var dragging: CustomAction.ID?
    /// The action the sheet edits; a new action is only added when its sheet is saved.
    @State private var editing: CustomAction?
    @State private var confirmRestore = false
    @State private var confirmDelete: CustomAction?

    var body: some View {
        Form {
            PageDescription(.actions)
            Section {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    ActionRow(action: action, index: index, count: actions.count, dragging: $dragging, open: { editing = action },
                              move: { move(action.id, by: $0) }, moveOnto: { moveOnto(dragged: $0, target: action.id) },
                              delete: { confirmDelete = action })
                }
            }
            Section {
                HStack {
                    Button("Add Action", systemImage: "plus") {
                        editing = CustomAction(title: "New action", symbol: "sparkles", prompt: "", kind: .other)
                    }
                    .disabled(actions.count >= RetextSettings.maxActions)
                    .help(actions.count >= RetextSettings.maxActions ? "Up to \(RetextSettings.maxActions) actions, one per ⌥ shortcut" : "")
                    Spacer()
                    Button("Restore Default Actions…", role: .destructive) { confirmRestore = true }
                        .foregroundStyle(.red)
                }
            }
        }
        // A drop anywhere else in the pane still ends the drag.
        .onDrop(of: [.text], delegate: DragCleanupDelegate(dragging: $dragging))
        .sheet(item: $editing) { action in
            ActionSheet(action: action, isNew: !actions.contains { $0.id == action.id },
                        save: save, delete: { delete(action.id); editing = nil })
        }
        .onAppear {
            switch SettingsView.demoExtra {
            case "expand", "icons": editing = actions.first
            case "restore": confirmRestore = true
            default: break
            }
        }
        .confirmationDialog("Restore the default actions?", isPresented: $confirmRestore) {
            Button("Restore Default Actions", role: .destructive) { actions = RetextSettings.defaultActions }
            // Cancel is the default button, so Return never restores.
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: {
            Text("Edited prompts and added actions are lost.")
        }
        .dialogSeverity(.critical)
        .confirmationDialog("Delete “\(confirmDelete?.title ?? "")”?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            presenting: confirmDelete) { action in
            Button("Delete Action", role: .destructive) { delete(action.id) }
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: { _ in
            Text("Its prompt is lost, and the actions after it move up one shortcut.")
        }
    }

    private func save(_ action: CustomAction) {
        if let i = actions.firstIndex(where: { $0.id == action.id }) {
            actions[i] = action
        } else if actions.count < RetextSettings.maxActions {
            actions.append(action)
        }
        editing = nil
    }

    private func delete(_ id: CustomAction.ID) { actions.removeAll { $0.id == id } }

    private func move(_ id: CustomAction.ID, by offset: Int) {
        guard let i = actions.firstIndex(where: { $0.id == id }), actions.indices.contains(i + offset) else { return }
        actions.swapAt(i, i + offset)
    }

    /// Puts the dragged action where the target is, so the rows between them shift by one.
    private func moveOnto(dragged: CustomAction.ID, target: CustomAction.ID) {
        guard dragged != target, let from = actions.firstIndex(where: { $0.id == dragged }),
              let to = actions.firstIndex(where: { $0.id == target }) else { return }
        actions.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }
}

/// Moves the dragged action onto this row as soon as the drag enters it.
private struct ActionDropDelegate: DropDelegate {
    @Binding var dragging: CustomAction.ID?
    let reduceMotion: Bool
    let moveOnto: (CustomAction.ID) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func dropEntered(info: DropInfo) {
        guard let dragging else { return }
        if reduceMotion {
            moveOnto(dragging)
        } else {
            withAnimation(.easeInOut(duration: 0.12)) { moveOnto(dragging) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Ends a drag dropped outside the rows.
private struct DragCleanupDelegate: DropDelegate {
    @Binding var dragging: CustomAction.ID?

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Drag handle, then icon, title, kind and shortcut as a plain button that opens the editor. The whole row drags;
/// keyboard and VoiceOver users reorder with the context menu or the named actions.
private struct ActionRow: View {
    let action: CustomAction
    let index: Int, count: Int
    @Binding var dragging: CustomAction.ID?
    let open: () -> Void
    let move: (Int) -> Void
    let moveOnto: (CustomAction.ID) -> Void
    let delete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isDragged = dragging == action.id
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
                .accessibilityHidden(true)
            Button(action: open) {
                IconRow(symbol: symbol, tint: kindTint(action.kind), title: action.title.isEmpty ? "Untitled" : action.title) {
                    shortcut
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(action.title), \(kindName(action.kind)), Option \(index + 1)")
            .accessibilityHint("Opens the editor")
            .accessibilityAction(named: "Move Up") { move(-1) }
            .accessibilityAction(named: "Move Down") { move(1) }
        }
        .opacity(isDragged ? 0.5 : 1)
        .padding(.vertical, 2)
        .background {
            if isDragged {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.12)).padding(-4)
            }
        }
        .contentShape(Rectangle())
        .onDrag {
            dragging = action.id
            return NSItemProvider(object: action.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: ActionDropDelegate(dragging: $dragging, reduceMotion: reduceMotion, moveOnto: moveOnto))
        // With no mouse button down the drag is over, so a drag that ended outside the window stops dimming this row.
        .onHover { _ in if dragging != nil, NSEvent.pressedMouseButtons == 0 { dragging = nil } }
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: open)
            Divider()
            Button("Move Up", systemImage: "arrow.up") { move(-1) }.disabled(index == 0)
            Button("Move Down", systemImage: "arrow.down") { move(1) }.disabled(index == count - 1)
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive, action: delete)
        }
    }

    private var shortcut: some View {
        Text("⌥\(index + 1)")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    /// A symbol name no SF Symbol has (a hand-edited settings.json) shows a warning sign.
    private var symbol: String {
        NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil) == nil ? "exclamationmark.triangle" : action.symbol
    }
}

private func kindName(_ kind: ActionKind) -> String {
    switch kind {
    case .grammar: "Grammar"
    case .translate: "Translate"
    case .other: "Other"
    }
}

private func kindTint(_ kind: ActionKind) -> Color {
    switch kind {
    case .grammar: .green
    case .translate: .blue
    case .other: .purple
    }
}

/// The editor sheet: works on a copy, so Cancel (or Escape) leaves the action as it was and Done saves it.
private struct ActionSheet: View {
    @State private var action: CustomAction
    let isNew: Bool
    let save: (CustomAction) -> Void
    let delete: () -> Void
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    init(action: CustomAction, isNew: Bool, save: @escaping (CustomAction) -> Void, delete: @escaping () -> Void) {
        _action = State(initialValue: action)
        self.isNew = isNew
        self.save = save
        self.delete = delete
    }

    var body: some View {
        let defaultPrompt = RetextSettings.defaultPrompt(for: action)
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Action" : "Edit Action").font(.title2.bold())
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Title").gridColumnAlignment(.trailing)
                    TextField("Title", text: $action.title, prompt: Text("e.g. Shorter")).labelsHidden()
                }
                GridRow {
                    Text("Icon")
                    IconPicker(symbol: $action.symbol)
                }
                GridRow {
                    Text("Kind")
                    Picker("Kind", selection: $action.kind) {
                        Text("Grammar").tag(ActionKind.grammar)
                        Text("Translate").tag(ActionKind.translate)
                        Text("Other").tag(ActionKind.other)
                    }
                    .labelsHidden().fixedSize()
                    .help("Grammar and Translate keep a one-line text on one line unless an app style applies, and a Grammar result much longer than the text is rejected. Other has no such checks.")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Prompt").font(.headline)
                    Spacer()
                    PullDownButton("Insert Example", systemImage: "plus", items: Self.examples.map { example in
                        .action(example) { insert(example) }
                    })
                    .fixedSize()
                    .help("Adds an example instruction to the end of the prompt")
                    Button("Reset Prompt") { if let defaultPrompt { action.prompt = defaultPrompt } }
                        .disabled(defaultPrompt == nil || defaultPrompt == action.prompt)
                        .help("Puts back the built-in prompt for Grammar, or for Translate into the language named in the title.")
                }
                // TextEditor, not a vertical TextField: Return starts a new line instead of ending the edit.
                TextEditor(text: $action.prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(nsColor: .separatorColor))
                    }
                    .overlay(alignment: .topLeading) {
                        if action.prompt.isEmpty {
                            Text("What Retext should do with the selected text")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 120, maxHeight: .infinity)
                    .accessibilityLabel("Prompt")
            }
            HStack {
                if !isNew {
                    Button("Delete Action…", role: .destructive) { confirmDelete = true }.foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Action" : "Done") { save(action) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 900, minHeight: 420, idealHeight: 520, maxHeight: 900)
        // On the sheet, not the pane: an alert presented while the sheet closes may not show at all.
        .confirmationDialog("Delete “\(action.title)”?", isPresented: $confirmDelete) {
            Button("Delete Action", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: {
            Text("Its prompt is lost, and the actions after it move up one shortcut.")
        }
    }

    private static let examples = ["Make it shorter and keep the meaning.", "Rewrite it more politely.", "Rewrite it in a formal business tone.",
                                   "Turn it into a bulleted list.", "Make it sound friendlier and more casual."]

    /// An empty prompt becomes the example; otherwise the example is added on a new line.
    private func insert(_ example: String) {
        let prompt = action.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        action.prompt = prompt.isEmpty ? example : prompt + "\n" + example
    }
}

/// A button showing the action's icon that opens a grid of symbols suited to text actions.
private struct IconPicker: View {
    @Binding var symbol: String
    @State private var picking = false

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
        .task {
            // The demo opens the grid once the sheet is up; presented together, the popover has no anchor yet.
            guard SettingsView.demoExtra == "icons" else { return }
            try? await Task.sleep(for: .milliseconds(400))
            picking = true
        }
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
