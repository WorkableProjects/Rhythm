import RhythmCore
import SwiftData
import SwiftUI

/// Main Reminders tab view: interactive management of active, snoozed, and completed reminders.
struct RemindersView: View {
    @Environment(AppModel.self) private var model
    @Query private var allRules: [ReminderRule]

    @State private var selectedStatus: ReminderStatusFilter = .active
    @State private var isAddingReminder = false
    @State private var quickTitle = ""
    @State private var editingReminder: ReminderRule?

    enum ReminderStatusFilter: String, CaseIterable, Identifiable {
        case active = "Active"
        case snoozed = "Snoozed"
        case completed = "Completed"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: RhythmSpacing.md) {
                // Status Filter Segmented Control
                Picker("Status Filter", selection: $selectedStatus) {
                    ForEach(ReminderStatusFilter.allCases) { filter in
                        Text("\(filter.rawValue) (\(count(for: filter)))").tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, RhythmSpacing.lg)
                .padding(.top, RhythmSpacing.sm)

                // Quick Add Row
                HStack(spacing: RhythmSpacing.sm) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)

                    TextField("Add a reminder…", text: $quickTitle)
                        .textFieldStyle(.plain)
                        .submitLabel(.done)
                        .onSubmit(addQuickReminder)

                    if !quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Add") {
                            addQuickReminder()
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(RhythmSpacing.md)
                .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.row, style: .continuous))
                .padding(.horizontal, RhythmSpacing.lg)

                // Reminders List
                let filtered = filteredReminders
                if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: emptySymbol)
                    } description: {
                        Text(emptyDescription)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filtered) { rule in
                            ReminderRowView(rule: rule, onEdit: { editingReminder = rule })
                                .listRowBackground(RhythmSurface.content)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                        .onDelete(perform: deleteReminders)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(RhythmSurface.background)
            .navigationTitle("Reminders")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingReminder = true
                    } label: {
                        Label("New Reminder", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingReminder) {
                NewReminderSheet()
            }
            .sheet(item: $editingReminder) { rule in
                EditReminderSheet(rule: rule)
            }
        }
    }

    private var filteredReminders: [ReminderRule] {
        allRules.filter { rule in
            switch selectedStatus {
            case .active:
                return rule.status == .active
            case .snoozed:
                return rule.status == .snoozed
            case .completed:
                return rule.status == .completed
            }
        }
        .sorted { r1, r2 in
            if r1.priority != r2.priority {
                return priorityOrder(r1.priority) > priorityOrder(r2.priority)
            }
            return r1.createdAt > r2.createdAt
        }
    }

    private func count(for filter: ReminderStatusFilter) -> Int {
        allRules.filter { rule in
            switch filter {
            case .active: return rule.status == .active
            case .snoozed: return rule.status == .snoozed
            case .completed: return rule.status == .completed
            }
        }.count
    }

    private func priorityOrder(_ priority: ReminderPriority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }

    private var emptyTitle: String {
        switch selectedStatus {
        case .active: return "No Active Reminders"
        case .snoozed: return "No Snoozed Reminders"
        case .completed: return "No Completed Reminders"
        }
    }

    private var emptySymbol: String {
        switch selectedStatus {
        case .active: return "checkmark.circle"
        case .snoozed: return "clock"
        case .completed: return "tray"
        }
    }

    private var emptyDescription: String {
        switch selectedStatus {
        case .active: return "You’re all caught up! Tap + or type above to add one."
        case .snoozed: return "No reminders are currently snoozed."
        case .completed: return "Completed reminders will appear here."
        }
    }

    private func addQuickReminder() {
        let trimmed = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.commit {
            model.repository.createReminder(title: trimmed)
        }
        quickTitle = ""
    }

    private func deleteReminders(at offsets: IndexSet) {
        let items = filteredReminders
        model.commit {
            for index in offsets {
                let rule = items[index]
                model.repository.deleteReminder(rule)
            }
        }
    }
}

/// An interactive row representing a single reminder item.
struct ReminderRowView: View {
    @Environment(AppModel.self) private var model
    let rule: ReminderRule
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: RhythmSpacing.md) {
            // Completion Toggle Button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    toggleCompletion()
                }
            } label: {
                Image(systemName: rule.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(rule.status == .completed ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
                HStack(spacing: RhythmSpacing.xs) {
                    Text(rule.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(rule.status == .completed, color: .secondary)
                        .foregroundStyle(rule.status == .completed ? .secondary : .primary)

                    if rule.priority == .high {
                        Text("!")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
                    }
                }

                if let body = rule.body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: RhythmSpacing.sm) {
                    if let period = rule.period {
                        Label(period.title, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }

                    if let dueDate = rule.dueDate {
                        let timeStr = rule.dueTime.map { " at \($0.shortTime)" } ?? ""
                        Label("\(dueDate.key)\(timeStr)", systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if rule.status == .snoozed, let snoozed = rule.snoozedUntil {
                        Label("Snoozed until \(snoozed.formatted(date: .omitted, time: .shortened))", systemImage: "moon.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 0)

            // Snooze / More Menu
            Menu {
                if rule.status == .active {
                    Button {
                        snooze(minutes: 15)
                    } label: {
                        Label("Snooze 15 minutes", systemImage: "timer")
                    }

                    Button {
                        snooze(minutes: 60)
                    } label: {
                        Label("Snooze 1 hour", systemImage: "clock")
                    }

                    Button {
                        snooze(minutes: 1440)
                    } label: {
                        Label("Snooze until tomorrow", systemImage: "sun.max")
                    }
                } else if rule.status == .snoozed {
                    Button {
                        unsnooze()
                    } label: {
                        Label("Resume Now", systemImage: "play.circle")
                    }
                }

                Button {
                    onEdit()
                } label: {
                    Label("Edit Details", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    model.commit { model.repository.deleteReminder(rule) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(RhythmSpacing.md)
        .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.row, style: .continuous))
    }

    private func toggleCompletion() {
        model.commit {
            if rule.status == .completed {
                model.repository.setReminderStatus(rule, status: .active)
            } else {
                model.repository.setReminderStatus(rule, status: .completed)
            }
        }
    }

    private func snooze(minutes: Int) {
        model.commit {
            let snoozedUntil = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
            model.repository.setReminderStatus(rule, status: .snoozed, snoozedUntil: snoozedUntil)
        }
    }

    private func unsnooze() {
        model.commit {
            model.repository.setReminderStatus(rule, status: .active)
        }
    }
}

/// Sheet to create a brand new detailed reminder.
struct NewReminderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var priority: ReminderPriority = .medium
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var selectedPeriodID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Title", text: $title)
                    TextField("Notes (optional)", text: $bodyText)
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(ReminderPriority.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Schedule & Due Date") {
                    Toggle("Set Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }

                    Picker("Linked Period", selection: $selectedPeriodID) {
                        Text("None (Standalone)").tag(UUID?.none)
                        ForEach(allPeriods) { period in
                            Text(period.title).tag(UUID?.some(period.id))
                        }
                    }
                }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveReminder()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var allPeriods: [SchedulePeriod] {
        model.repository.templates().flatMap(\.sortedPeriods)
    }

    private func saveReminder() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let localDate: LocalDate? = hasDueDate ? LocalDate(dueDate, calendar: model.calendar) : nil
        let clockTime: ClockTime? = hasDueDate ? ClockTime(dueDate, calendar: model.calendar) : nil

        let period = selectedPeriodID.flatMap { model.repository.period(id: $0) }
        let trigger: ReminderTrigger
        if let period {
            trigger = .beforeStart(minutes: 0)
        } else {
            trigger = .standalone(date: localDate, time: clockTime)
        }

        model.commit {
            model.repository.createReminder(
                title: trimmedTitle,
                body: bodyText.isEmpty ? nil : bodyText,
                trigger: trigger,
                priority: priority,
                dueDate: localDate,
                dueTime: clockTime,
                period: period
            )
        }
    }
}

/// Sheet to edit an existing reminder's details.
struct EditReminderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let rule: ReminderRule

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var priority: ReminderPriority = .medium
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $bodyText)
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(ReminderPriority.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Due Date") {
                    Toggle("Set Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .navigationTitle("Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                title = rule.title
                bodyText = rule.body ?? ""
                priority = rule.priority
                if let d = rule.dueDate {
                    hasDueDate = true
                    let time = rule.dueTime ?? ClockTime(hour: 9, minute: 0)
                    dueDate = d.date(at: time, in: model.calendar) ?? Date()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveChanges() {
        model.commit {
            rule.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            rule.body = bodyText.isEmpty ? nil : bodyText
            rule.priority = priority
            if hasDueDate {
                rule.dueDate = LocalDate(dueDate, calendar: model.calendar)
                rule.dueTime = ClockTime(dueDate, calendar: model.calendar)
            } else {
                rule.dueDate = nil
                rule.dueTime = nil
            }
        }
    }
}
