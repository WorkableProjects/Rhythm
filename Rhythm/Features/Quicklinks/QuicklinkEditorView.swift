import RhythmCore
import SwiftUI

/// Creates or edits a Quicklink with live URL validation. Unknown schemes are never rewritten;
/// a missing `https://` is offered as a suggestion the user can accept.
struct QuicklinkEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let link: Quicklink?

    @State private var title: String
    @State private var urlString: String
    @State private var symbolName: String
    @State private var category: QuicklinkCategory?
    @State private var note: String
    @State private var isFavorite: Bool

    static let symbolChoices = [
        "safari", "link", "graduationcap", "book", "doc.text", "calendar", "envelope", "bubble.left",
        "music.note", "pencil.and.ruler", "function", "globe", "video", "folder", "square.stack.3d.up", "star"
    ]

    init(link: Quicklink?) {
        self.link = link
        _title = State(initialValue: link?.title ?? "")
        _urlString = State(initialValue: link?.urlString ?? "")
        _symbolName = State(initialValue: link?.symbolName ?? "")
        _category = State(initialValue: link?.category)
        _note = State(initialValue: link?.note ?? "")
        _isFavorite = State(initialValue: link?.isFavorite ?? false)
    }

    private var validation: Result<ValidatedQuicklinkURL, QuicklinkURLError> {
        QuicklinkURLValidator.validate(urlString)
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        if case .success = validation { return !trimmedTitle.isEmpty }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("quicklinkTitleField")
                    TextField("https://example.com", text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .accessibilityIdentifier("quicklinkURLField")
                } footer: {
                    validationFooter
                }

                Section("Details") {
                    Picker("Icon", selection: $symbolName) {
                        Label("Automatic", systemImage: inferredKind.defaultSymbolName).tag("")
                        ForEach(Self.symbolChoices, id: \.self) { symbol in
                            Label(symbol.replacingOccurrences(of: ".", with: " ").capitalized, systemImage: symbol).tag(symbol)
                        }
                    }
                    Picker("Category", selection: $category) {
                        Text("None").tag(QuicklinkCategory?.none)
                        ForEach(QuicklinkCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(Optional(category))
                        }
                    }
                    TextField("Note (optional)", text: $note)
                    Toggle("Show on Today", isOn: $isFavorite)
                }

                Section {
                    DisclosureGroup("Opening a Shortcut") {
                        Text("Use a link like shortcuts://run-shortcut?name=Study%20Mode. iOS opens the Shortcuts app, which may ask you to confirm. Rhythm can’t see or run your shortcuts by itself.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(link == nil ? "New Quicklink" : "Edit Quicklink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("saveQuicklinkButton")
                }
            }
        }
    }

    private var inferredKind: QuicklinkKind {
        if case .success(let value) = validation { return value.kind }
        return .website
    }

    @ViewBuilder
    private var validationFooter: some View {
        let isEmpty = urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch validation {
        case .success(let value):
            VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
                Label(value.kind.displayName, systemImage: value.kind.defaultSymbolName)
                if let warning = value.warning {
                    Text(warning)
                }
            }
        case .failure(let error) where !isEmpty:
            VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("quicklinkURLError")
                if case .missingScheme(let suggestion?) = error {
                    Button("Use \(suggestion)") { urlString = suggestion }
                        .font(.footnote.weight(.semibold))
                }
            }
        case .failure:
            Text("A website, app link, or Shortcut link.")
        }
    }

    private func save() {
        guard case .success(let validated) = validation else { return }
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = model.commit {
            if let link {
                link.title = trimmedTitle
                link.urlString = trimmedURL
                link.kind = validated.kind
                link.symbolName = symbolName.isEmpty ? nil : symbolName
                link.category = category
                link.note = trimmedNote.isEmpty ? nil : trimmedNote
                link.isFavorite = isFavorite
            } else {
                model.repository.addQuicklink(QuicklinkDefinition(
                    title: trimmedTitle,
                    urlString: trimmedURL,
                    kind: validated.kind,
                    symbolName: symbolName.isEmpty ? nil : symbolName,
                    category: category,
                    note: trimmedNote.isEmpty ? nil : trimmedNote,
                    isFavorite: isFavorite
                ))
            }
        }
        if saved { dismiss() }
    }
}
