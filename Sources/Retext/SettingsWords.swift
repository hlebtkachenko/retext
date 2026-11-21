import RetextCore
import SwiftUI

// MARK: Protected Words

struct WordsPane: View {
    @Binding var settings: RetextSettings
    @State private var newWord = ""
    /// The add field takes the focus, so typing on opening the pane never overwrites a saved word.
    @FocusState private var adding: Bool

    var body: some View {
        Form {
            PageDescription(.words)
            Section {
                ForEach(settings.protectedWords, id: \.self) { word in
                    WordRow(word: word,
                            commit: { settings.editProtectedWord(word, to: $0) },
                            remove: { settings.protectedWords.removeAll { $0 == word } })
                }
                HStack {
                    // Multi-line, so a pasted list keeps its lines; Return adds every term.
                    TextField("New word", text: $newWord, prompt: Text("Add words, one per line or separated by commas"), axis: .vertical)
                        .lineLimit(1...6).labelsHidden().onSubmit(add)
                        .focused($adding)
                    Button("Add", action: add).disabled(RetextSettings.terms(in: newWord).isEmpty)
                }
            } footer: {
                Text("Click a word to edit it.").foregroundStyle(.secondary)
            }
        }
        .onAppear { adding = true }
    }

    private func add() {
        settings.addProtectedWords(newWord)
        newWord = ""
    }
}

/// One protected word, editable in place: the draft is saved on Return or when the field loses focus.
private struct WordRow: View {
    let word: String
    let commit: (String) -> Void
    let remove: () -> Void
    @State private var draft: String
    @FocusState private var focused: Bool

    init(word: String, commit: @escaping (String) -> Void, remove: @escaping () -> Void) {
        self.word = word
        self.commit = commit
        self.remove = remove
        _draft = State(initialValue: word)
    }

    var body: some View {
        HStack {
            TextField("Protected word", text: $draft)
                .labelsHidden()
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
                // Switching panes or closing the window doesn't always end the focus first.
                .onDisappear(perform: save)
            Button("Remove \(word)", systemImage: "minus.circle", action: remove)
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .help("Remove")
        }
        .contextMenu { Button("Remove", role: .destructive, action: remove) }
        .accessibilityAction(named: "Remove", remove)
    }

    /// Safe to run twice (Return, then losing focus): an unchanged word is a no-op. A changed word gets a new row;
    /// a draft that saves as the same word (" Acme ") snaps back to it.
    private func save() {
        guard draft != word else { return }
        commit(draft)
        draft = word
    }
}
