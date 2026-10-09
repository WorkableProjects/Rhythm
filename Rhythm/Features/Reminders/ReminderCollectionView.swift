import RhythmCore
import SwiftUI

/// What the reminder editor sheet is showing.
struct ReminderEditorTarget: Identifiable, Hashable {
    var reminder: NativeReminder
    var isNew: Bool
    var id: UUID { reminder.id }
}

/// One smart list (Today, Scheduled, …) or a user list, grouped by due date, with a quick-add bar.
struct ReminderCollectionView: View {
    @Environment(AppModel.self) private var model
    let filter: ReminderFilter

    @State private var quickText = ""
    @State private var editing: ReminderEditorTarget?
    @State private var showsCompleted = false
    @State private var isEditingList = false
    @State private var isConfirmingClear = false
    @FocusState private var isQuickAddFocused: Bool

    private var library: NativeReminderLibrary { model.reminders.library }

    private var list: NativeReminderList? {
        if case .list(let id) = filter { return library.list(id) }
        return nil
    }

    private var title: String { list?.name ?? filter.title }

    private var tint: Color {
        if let list { return ReminderFormat.tint(forListKey: list.colorKey) }
        return filter.tint
    }

    private var canAdd: Bool { filter != .completed }

    var body: some View {
        _ = model.clockEpoch
        let calendar = model.calendar
        let today = model.today
        let open = library.items(for: filter, today: today, calendar: calendar)
        let completed: [NativeReminder] = {
            guard showsCompleted, case .list(let id) = filter else { return [] }
            return library.completedReminders(in: id)
        }()
        let sections = filter == .completed ? [] : NativeReminderLibrary.sections(for: open, today: today, calendar: calendar)

        return Group {
            if open.isEmpty && completed.isEmpty {
                emptyState
            } else {
                List {
                    if filter == .completed {
                        ForEach(open) { row($0, showsList: true) }
                    } else {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.reminders) { row($0, showsList: list == nil) }
                            } header: {
                                if !(sections.count == 1 && section.bucket == .noDate) {
                                    Text(ReminderFormat.title(for: section.bucket, calendar: calendar))
                                        .foregroundStyle(section.bucket == .overdue ? Color.red : Color.secondary)
                                }
                            }
                        }
                        if !completed.isEmpty {
                            Section("Completed") {
                                ForEach(completed) { row($0, showsList: false) }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .animation(RhythmMotion.stateChange, value: open.map(\.id))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .tint(tint)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if canAdd { quickAddBar(today: today, calendar: calendar) }
        }
        .sheet(item: $editing) { target in
            NativeReminderEditor(reminder: target.reminder, isNew: target.isNew)
        }
        .sheet(isPresented: $isEditingList) {
            if let list { ReminderListEditor(list: list) }
        }
        .confirmationDialog("Delete completed reminders?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Delete Completed", role: .destructive) {
                if case .list(let id) = filter { model.reminders.clearCompleted(in: id) } else { model.reminders.clearCompleted() }
            }
        } message: {
            Text("This can’t be undone.")
        }
    }

    private func row(_ reminder: NativeReminder, showsList: Bool) -> some View {
        ReminderRow(reminder: reminder, showsList: showsList) {
            editing = ReminderEditorTarget(reminder: reminder, isNew: false)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: filter == .completed ? "checkmark.circle" : "checklist")
        } description: {
            Text(emptyDescription)
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .today: "Nothing Due Today"
        case .scheduled: "Nothing Scheduled"
        case .flagged: "No Flagged Reminders"
        case .completed: "Nothing Completed Yet"
        default: "No Reminders"
        }
    }

    private var emptyDescription: String {
        switch filter {
        case .completed: "Reminders you finish show up here."
        case .flagged: "Flag important reminders to find them quickly."
        default: "Type below to add one. Try “Turn in essay tomorrow 3pm !high”."
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if case .list = filter {
                    Toggle(isOn: $showsCompleted.animation()) {
                        Label("Show Completed", systemImage: "checkmark.circle")
                    }
                    Button { isEditingList = true } label: { Label("Edit List", systemImage: "pencil") }
                }
                if filter == .completed || showsCompleted {
                    Button(role: .destructive) { isConfirmingClear = true } label: {
                        Label("Delete Completed", systemImage: "trash")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(!hasMenuItems)
        }
    }

    private var hasMenuItems: Bool {
        if case .list = filter { return true }
        return filter == .completed
    }

    private func quickAddBar(today: LocalDate, calendar: Calendar) -> some View {
        let parsed = quickText.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : ReminderQuickAdd.parse(quickText, today: today, calendar: calendar)
        return VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
            if let parsed, parsed.dueDate != nil || parsed.priority != .none || parsed.isFlagged {
                quickAddPreview(parsed, today: today, calendar: calendar)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: RhythmSpacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                TextField("New Reminder", text: $quickText)
                    .focused($isQuickAddFocused)
                    .submitLabel(.done)
                    .onSubmit(submitQuickAdd)
                    .accessibilityIdentifier("quickAddField")
                if !quickText.isEmpty {
                    Button {
                        let parsed = ReminderQuickAdd.parse(quickText, today: today, calendar: calendar)
                        editing = ReminderEditorTarget(reminder: draft(from: parsed, today: today), isNew: true)
                        quickText = ""
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Add details")
                }
            }
            .padding(.horizontal, RhythmSpacing.lg)
            .padding(.vertical, RhythmSpacing.md)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, RhythmSpacing.lg)
        .padding(.bottom, RhythmSpacing.sm)
        .animation(RhythmMotion.stateChange, value: parsed?.dueDate)
    }

    private func quickAddPreview(_ parsed: ReminderQuickAdd, today: LocalDate, calendar: Calendar) -> some View {
        var parts: [String] = []
        if let date = parsed.dueDate {
            var text = ReminderFormat.dayName(date, today: today, calendar: calendar)
            if let time = parsed.dueTime { text += ", \(time.formatted(calendar: calendar))" }
            parts.append(text)
        }
        if parsed.priority != .none { parts.append("\(parsed.priority.displayName) priority") }
        if parsed.isFlagged { parts.append("Flagged") }
        return Label(parts.joined(separator: " · "), systemImage: "sparkles")
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, RhythmSpacing.md)
            .padding(.vertical, RhythmSpacing.xs)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private var defaultListID: UUID? {
        if case .list(let id) = filter { return id }
        return nil
    }

    /// A reminder in a Today list defaults to today; in Flagged, to flagged.
    private func defaults(today: LocalDate) -> (date: LocalDate?, flagged: Bool) {
        (filter == .today ? today : nil, filter == .flagged)
    }

    private func submitQuickAdd() {
        let today = model.today
        let fallback = defaults(today: today)
        model.reminders.quickAdd(quickText, defaultListID: defaultListID, defaultDate: fallback.date,
                                 defaultFlagged: fallback.flagged, today: today, calendar: model.calendar)
        quickText = ""
        isQuickAddFocused = true
    }

    private func draft(from parsed: ReminderQuickAdd, today: LocalDate) -> NativeReminder {
        let fallback = defaults(today: today)
        let named = parsed.listName.flatMap { name in
            library.lists.first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
        }
        return NativeReminder(title: parsed.title, listID: named?.id ?? defaultListID ?? library.defaultListID,
                              dueDate: parsed.dueDate ?? fallback.date, dueTime: parsed.dueTime,
                              priority: parsed.priority, isFlagged: parsed.isFlagged || fallback.flagged)
    }
}
