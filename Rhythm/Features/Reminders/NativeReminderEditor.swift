import RhythmCore
import SwiftUI

/// Creates or edits a native reminder: details, due date and time, alerts, repeat, priority,
/// flag, list, link, and a checklist.
struct NativeReminderEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool
    @State private var draft: NativeReminder
    @State private var hasDate: Bool
    @State private var hasTime: Bool
    @State private var dateValue: Date
    @State private var timeValue: Date
    @State private var isConfirmingDelete = false
    @FocusState private var focusedStep: UUID?

    init(reminder: NativeReminder, isNew: Bool) {
        self.isNew = isNew
        let calendar = Calendar.autoupdatingCurrent
        _draft = State(initialValue: reminder)
        _hasDate = State(initialValue: reminder.dueDate != nil)
        _hasTime = State(initialValue: reminder.dueTime != nil)
        _dateValue = State(initialValue: reminder.dueDate?.noon(in: calendar) ?? Date.now)
        _timeValue = State(initialValue: reminder.dueTime?.referenceDate(calendar: calendar)
            ?? ClockTime(hour: 9, minute: 0).referenceDate(calendar: calendar))
    }

    private var canSave: Bool { !draft.trimmedTitle.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                checklistSection
                dueSection
                organizeSection
                if !isNew { deleteSection }
            }
            .navigationTitle(isNew ? "New Reminder" : "Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Done", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("saveNativeReminderButton")
                }
            }
            .confirmationDialog("Delete this reminder?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Reminder", role: .destructive) {
                    model.reminders.delete([draft.id])
                    dismiss()
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Sections

    private var detailsSection: some View {
        Section {
            TextField("Title", text: $draft.title, axis: .vertical)
                .font(.headline)
                .accessibilityIdentifier("nativeReminderTitleField")
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(2...6)
            TextField("URL", text: Binding(get: { draft.urlString ?? "" }, set: { draft.urlString = $0.isEmpty ? nil : $0 }))
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var checklistSection: some View {
        Section("Checklist") {
            ForEach($draft.subtasks) { $step in
                HStack(spacing: RhythmSpacing.md) {
                    Button {
                        step.isDone.toggle()
                    } label: {
                        Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(step.isDone ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(step.isDone ? "Mark step incomplete" : "Mark step complete")
                    TextField("Step", text: $step.title)
                        .focused($focusedStep, equals: step.id)
                        .strikethrough(step.isDone)
                        .submitLabel(.next)
                        .onSubmit(addStep)
                }
            }
            .onDelete { draft.subtasks.remove(atOffsets: $0) }
            .onMove { draft.subtasks.move(fromOffsets: $0, toOffset: $1) }
            Button(action: addStep) {
                Label("Add Step", systemImage: "plus.circle.fill")
            }
        }
    }

    private var dueSection: some View {
        Section {
            Toggle(isOn: $hasDate.animation()) {
                Label("Date", systemImage: "calendar")
            }
            if hasDate {
                DatePicker("Date", selection: $dateValue, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                quickDateButtons
                Toggle(isOn: $hasTime.animation()) {
                    Label("Time", systemImage: "clock")
                }
                if hasTime {
                    DatePicker("Time", selection: $timeValue, displayedComponents: .hourAndMinute)
                    Picker(selection: $draft.alertMinutesBefore) {
                        ForEach(ReminderFormat.alertChoices, id: \.self) { minutes in
                            Text(ReminderFormat.alertText(minutes: minutes)).tag(minutes)
                        }
                    } label: {
                        Label("Alert", systemImage: "bell")
                    }
                }
                Picker(selection: $draft.repeatRule) {
                    ForEach(ReminderRepeat.allCases) { Text($0.displayName).tag($0) }
                } label: {
                    Label("Repeat", systemImage: "repeat")
                }
            }
        } footer: {
            if hasDate && !hasTime {
                Text("All-day reminders alert at 9:00 AM.")
            }
        }
    }

    private var quickDateButtons: some View {
        let calendar = model.calendar
        return HStack(spacing: RhythmSpacing.sm) {
            ForEach([("Today", 0), ("Tomorrow", 1), ("Next Week", 7)], id: \.1) { name, days in
                Button(name) {
                    dateValue = model.today.adding(days: days, calendar: calendar).noon(in: calendar)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var organizeSection: some View {
        Section {
            Picker(selection: $draft.listID) {
                ForEach(model.reminders.library.sortedLists) { list in
                    Label {
                        Text(list.name)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(ReminderFormat.tint(forListKey: list.colorKey))
                    }
                    .tag(list.id)
                }
            } label: {
                Label("List", systemImage: "list.bullet")
            }
            Picker(selection: $draft.priority) {
                ForEach(ReminderPriority.allCases) { Text($0.displayName).tag($0) }
            } label: {
                Label("Priority", systemImage: "exclamationmark.3")
            }
            Toggle(isOn: $draft.isFlagged) {
                Label("Flag", systemImage: "flag")
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Reminder", role: .destructive) { isConfirmingDelete = true }
        }
    }

    // MARK: Actions

    private func addStep() {
        let step = ReminderSubtask(title: "")
        draft.subtasks.append(step)
        focusedStep = step.id
    }

    private func save() {
        let calendar = model.calendar
        var saved = draft
        saved.title = draft.trimmedTitle
        saved.subtasks = draft.subtasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        let url = draft.urlString?.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.urlString = (url?.isEmpty ?? true) ? nil : url
        if hasDate {
            saved.dueDate = LocalDate(dateValue, calendar: calendar)
            saved.dueTime = hasTime ? ClockTime(referenceDate: timeValue, calendar: calendar) : nil
            if !hasTime { saved.alertMinutesBefore = 0 }
        } else {
            saved.dueDate = nil
            saved.dueTime = nil
            saved.repeatRule = .never
        }
        model.reminders.save(saved)
        dismiss()
    }
}
