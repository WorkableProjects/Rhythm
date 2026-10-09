import RhythmCore
import SwiftUI

/// Creates or edits a reminder list: name, colour, and symbol.
struct ReminderListEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool
    @State private var draft: NativeReminderList
    @State private var isConfirmingDelete = false

    static let symbols = [
        "list.bullet", "book.closed", "graduationcap", "pencil.and.ruler", "backpack", "flask", "music.note",
        "figure.run", "sportscourt", "paintpalette", "laptopcomputer", "cart", "house", "star", "heart",
        "gift", "airplane", "briefcase", "fork.knife", "bell"
    ]

    init(list: NativeReminderList?) {
        isNew = list == nil
        _draft = State(initialValue: list ?? NativeReminderList(name: ""))
    }

    private var tint: Color { ReminderFormat.tint(forListKey: draft.colorKey) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: RhythmSpacing.md) {
                        Image(systemName: draft.symbolName)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(tint.gradient, in: Circle())
                            .accessibilityHidden(true)
                        TextField("List Name", text: $draft.name)
                            .multilineTextAlignment(.center)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(tint)
                            .accessibilityIdentifier("reminderListNameField")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, RhythmSpacing.sm)
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: RhythmSpacing.lg) {
                        ForEach(RhythmPalette.periodColorKeys, id: \.self) { key in
                            Button {
                                draft.colorKey = key
                            } label: {
                                Circle()
                                    .fill(ReminderFormat.tint(forListKey: key))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if draft.colorKey == key {
                                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(key.capitalized)
                            .accessibilityAddTraits(draft.colorKey == key ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, RhythmSpacing.xs)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: RhythmSpacing.lg) {
                        ForEach(Self.symbols, id: \.self) { symbol in
                            Button {
                                draft.symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .foregroundStyle(draft.symbolName == symbol ? Color.white : Color.primary)
                                    .frame(width: 44, height: 44)
                                    .background(draft.symbolName == symbol ? tint : Color.secondary.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(draft.symbolName == symbol ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, RhythmSpacing.xs)
                }
                if !isNew && model.reminders.library.lists.count > 1 {
                    Section {
                        Button("Delete List", role: .destructive) { isConfirmingDelete = true }
                    } footer: {
                        Text("Deleting a list also deletes its reminders.")
                    }
                }
            }
            .navigationTitle(isNew ? "New List" : "Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Done") {
                        var saved = draft
                        saved.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.reminders.saveList(saved)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveReminderListButton")
                }
            }
            .confirmationDialog("Delete “\(draft.name)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete List", role: .destructive) {
                    model.reminders.deleteList(draft.id)
                    model.router.reminderListDeleted = draft.id
                    dismiss()
                }
            }
        }
    }
}
