import RhythmCore
import SwiftUI

/// The template or date-specific schedule a period belongs to.
enum PeriodOwner {
    case template(ScheduleTemplate)
    case dateOverride(ScheduleOverride)

    init?(period: SchedulePeriod) {
        if let template = period.template {
            self = .template(template)
        } else if let override = period.dateOverride {
            self = .dateOverride(override)
        } else {
            return nil
        }
    }

    var periods: [SchedulePeriod] {
        switch self {
        case .template(let template): template.periods
        case .dateOverride(let override): override.periods
        }
    }
}

/// Creates or edits a period. Conflicts are validated live against the other periods in the
/// same schedule, and saving is disabled until they are resolved.
struct PeriodEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let owner: PeriodOwner
    let period: SchedulePeriod?

    @State private var draft: PeriodDefinition
    @State private var reminders: [ReminderDefinition]
    @State private var editingReminder: ReminderDefinition?
    @State private var isConfirmingDelete = false

    init(owner: PeriodOwner, period: SchedulePeriod?) {
        self.owner = owner
        self.period = period
        if let period {
            _draft = State(initialValue: period.definition)
            _reminders = State(initialValue: period.reminders.compactMap(\.definition).sorted { $0.title < $1.title })
        } else {
            _draft = State(initialValue: Self.suggestedNewPeriod(after: owner.periods))
            _reminders = State(initialValue: [])
        }
    }

    private var isNew: Bool { period == nil }

    /// Issues that involve this period (title, range, or overlaps with siblings).
    private var issues: [ScheduleIssue] {
        let siblings = owner.periods.filter { $0.id != draft.id }.map(\.definition)
        return ScheduleValidator.validate(periods: siblings + [draft]).filter { $0.periodIDs.contains(draft.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                timeSection
                appearanceSection
                RemindersSection(
                    reminders: $reminders,
                    periodID: draft.id,
                    onAdd: { editingReminder = ReminderDefinition(periodID: draft.id, title: "", trigger: .beforeStart(minutes: 10)) },
                    onEdit: { editingReminder = $0 }
                )
                if !isNew {
                    Section {
                        Button("Delete Period", role: .destructive) { isConfirmingDelete = true }
                            .accessibilityIdentifier("deletePeriodButton")
                    }
                }
            }
            .navigationTitle(isNew ? "New Period" : "Edit Period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!issues.isEmpty)
                        .accessibilityIdentifier("savePeriodButton")
                }
            }
            .sheet(item: $editingReminder) { reminder in
                ReminderEditorView(reminder: reminder) { saved in
                    if let index = reminders.firstIndex(where: { $0.id == saved.id }) {
                        reminders[index] = saved
                    } else {
                        reminders.append(saved)
                    }
                }
            }
            .confirmationDialog("Delete “\(draft.title)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Period", role: .destructive, action: delete)
            } message: {
                Text("Its reminders will be removed too.")
            }
        }
    }

    // MARK: Sections

    private var detailsSection: some View {
        Section {
            TextField("Title", text: $draft.title)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("periodTitleField")
            Picker("Type", selection: $draft.kind) {
                ForEach(PeriodKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.defaultSymbolName).tag(kind)
                }
            }
            TextField("Room or teacher (optional)", text: Binding(
                get: { draft.detail ?? "" },
                set: { draft.detail = $0.isEmpty ? nil : $0 }
            ))
        }
    }

    private var timeSection: some View {
        Section {
            DatePicker("Starts", selection: Binding(
                get: { draft.start.referenceDate(calendar: model.calendar) },
                set: { draft.start = ClockTime(referenceDate: $0, calendar: model.calendar) }
            ), displayedComponents: .hourAndMinute)
            .accessibilityIdentifier("periodStartPicker")
            DatePicker("Ends", selection: Binding(
                get: { draft.end.referenceDate(calendar: model.calendar) },
                set: { draft.end = ClockTime(referenceDate: $0, calendar: model.calendar) }
            ), displayedComponents: .hourAndMinute)
            .accessibilityIdentifier("periodEndPicker")
            Toggle("Include in Schedule", isOn: $draft.isEnabled)
        } footer: {
            if issues.isEmpty {
                Text("\(CountdownFormat.short(TimeInterval(max(0, draft.durationMinutes) * 60))) long.")
            } else {
                VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
                    ForEach(issues) { issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .accessibilityIdentifier("periodIssues")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Color", selection: Binding(
                get: { draft.colorKey ?? "" },
                set: { draft.colorKey = $0.isEmpty ? nil : $0 }
            )) {
                Text("Automatic").tag("")
                ForEach(RhythmPalette.periodColorKeys, id: \.self) { key in
                    Label {
                        Text(key.capitalized)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(RhythmPalette.color(forKey: key) ?? .gray)
                    }
                    .tag(key)
                }
            }
            Picker("Symbol", selection: Binding(
                get: { draft.symbolName ?? "" },
                set: { draft.symbolName = $0.isEmpty ? nil : $0 }
            )) {
                Label("Automatic", systemImage: draft.kind.defaultSymbolName).tag("")
                ForEach(Self.symbolChoices, id: \.self) { symbol in
                    Label(Self.symbolName(symbol), systemImage: symbol).tag(symbol)
                }
            }
        }
    }

    // MARK: Actions

    private func save() {
        var definition = draft
        definition.title = definition.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let reminders = reminders
        let saved = model.commit {
            let stored: SchedulePeriod
            switch owner {
            case .template(let template): stored = model.repository.upsertPeriod(definition, in: template)
            case .dateOverride(let override): stored = model.repository.upsertPeriod(definition, in: override)
            }
            model.repository.setReminders(reminders, for: stored)
        }
        if saved { dismiss() }
    }

    private func delete() {
        guard let period else { return }
        if model.commit({ model.repository.deletePeriod(period) }) { dismiss() }
    }

    // MARK: Defaults

    /// A new period starts five minutes after the last one ends (or at 8:00) and lasts 50 minutes.
    static func suggestedNewPeriod(after periods: [SchedulePeriod]) -> PeriodDefinition {
        let lastEnd = periods.map(\.endMinute).filter { $0 < ClockTime.endOfDayMinutes }.max()
        let start = min(lastEnd.map { $0 + 5 } ?? 8 * 60, ClockTime.endOfDayMinutes - 50)
        return PeriodDefinition(
            title: "",
            kind: .classPeriod,
            start: ClockTime(minutesAfterMidnight: start),
            end: ClockTime(minutesAfterMidnight: start + 50),
            sortOrder: (periods.map(\.sortOrder).max() ?? -1) + 1
        )
    }

    static let symbolChoices = [
        "book.closed", "function", "flask", "globe.americas", "paintpalette", "music.note",
        "figure.run", "laptopcomputer", "character.book.closed", "theatermasks", "hammer", "leaf",
        "fork.knife", "cup.and.saucer", "figure.walk", "person.3", "star"
    ]

    static func symbolName(_ symbol: String) -> String {
        switch symbol {
        case "book.closed": "Book"
        case "function": "Math"
        case "flask": "Science"
        case "globe.americas": "Globe"
        case "paintpalette": "Art"
        case "music.note": "Music"
        case "figure.run": "Sports"
        case "laptopcomputer": "Computer"
        case "character.book.closed": "Language"
        case "theatermasks": "Drama"
        case "hammer": "Shop"
        case "leaf": "Nature"
        case "fork.knife": "Meal"
        case "cup.and.saucer": "Break"
        case "figure.walk": "Walk"
        case "person.3": "Group"
        default: "Star"
        }
    }
}

/// Reminder rules for a period, with a contextual permission request and a clear explanation
/// when notifications are off.
private struct RemindersSection: View {
    @Environment(AppModel.self) private var model
    @Binding var reminders: [ReminderDefinition]
    let periodID: UUID
    let onAdd: () -> Void
    let onEdit: (ReminderDefinition) -> Void

    var body: some View {
        Section {
            ForEach($reminders) { $reminder in
                HStack {
                    Button {
                        onEdit(reminder)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title.isEmpty ? "Reminder" : reminder.title)
                                .foregroundStyle(.primary)
                            Text(reminder.trigger.displaySummary(calendar: model.calendar))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("Enabled", isOn: $reminder.isEnabled)
                        .labelsHidden()
                }
            }
            .onDelete { reminders.remove(atOffsets: $0) }

            Button {
                Task {
                    // Ask only now, when the user chooses to add a reminder.
                    await model.notifications.requestAuthorizationIfNeeded()
                    onAdd()
                }
            } label: {
                Label("Add Reminder", systemImage: "bell.badge")
            }
            .accessibilityIdentifier("addReminderButton")
        } header: {
            Text("Reminders")
        } footer: {
            NotificationStatusFooter(hasReminders: !reminders.isEmpty)
        }
    }
}

/// Explains notification state without blocking the user.
struct NotificationStatusFooter: View {
    @Environment(AppModel.self) private var model
    var hasReminders: Bool

    var body: some View {
        switch model.notifications.authorization {
        case .denied where hasReminders:
            VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
                Text("Notifications are off for Rhythm, so these reminders are saved but won’t alert you.")
                Button("Turn On in Settings") { model.notifications.openSystemSettings() }
                    .font(.footnote.weight(.semibold))
            }
            .accessibilityIdentifier("notificationsDeniedNotice")
        case _ where hasReminders && !model.preferences.remindersEnabled:
            Text("Reminders are turned off in Rhythm’s settings.")
        default:
            Text("Reminders alert you before this period on every day it’s scheduled.")
        }
    }
}
