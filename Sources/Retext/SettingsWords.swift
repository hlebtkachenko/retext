import RetextCore
import SwiftUI

// MARK: Protected Words

struct WordsPane: View {
    @Binding var settings: RetextSettings
    @State private var newWord = ""

    var body: some View {
        Form {
            Section {
                ForEach(settings.protectedWords, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button("Remove \(word)", systemImage: "minus.circle") { settings.protectedWords.removeAll { $0 == word } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
                HStack {
                    // Multi-line, so a pasted list keeps its lines; Return adds every term.
                    TextField("New term", text: $newWord, prompt: Text("Add terms, one per line or separated by commas"), axis: .vertical)
                        .lineLimit(1...6).labelsHidden().onSubmit(add)
                    Button("Add", action: add).disabled(RetextSettings.terms(in: newWord).isEmpty)
                }
            } footer: {
                Text("Names and terms that are never changed or translated.").foregroundStyle(.secondary)
            }
        }
    }

    private func add() {
        settings.addProtectedWords(newWord)
        newWord = ""
    }
}
