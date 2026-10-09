import RhythmCore
import SwiftUI

/// The Reminders tab: smart lists with live counts, the user's lists, search, and quick creation.
/// Reminders here are independent of the school schedule.
struct RemindersView: View {
    @Environment(AppModel.self) private var model

    @State private var path: [ReminderFilter] = []
    @State private var search = ""
    @State private var editing: ReminderEditorTarget?
    @State private var isAddingList = false
    @State private var editingList: NativeReminderList?

    private var library: NativeReminderLibrary { model.reminders.library }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if search.trimmingCharacters(in: .whitespaces).isEmpty {
                    overview
                } else {
                    searchResults
                }
            }
            .background(RhythmSurface.background)
            .navigationTitle("Reminders")
            .searchable(text: $search, prompt: "Search Reminders")
            .navigationDestination(for: ReminderFilter.self) { ReminderCollectionView(filter: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.router.isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { startNewReminder() } label: { Label("New Reminder", systemImage: "plus.circle") }
                        Button { isAddingList = true } label: { Label("New List", systemImage: "list.bullet.rectangle") }
                            .accessibilityIdentifier("newReminderListMenuItem")
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .accessibilityIdentifier("remindersAddMenu")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if search.isEmpty { newReminderButton }
            }
        }
        .sheet(item: $editing) { NativeReminderEditor(reminder: $0.reminder, isNew: $0.isNew) }
        .sheet(isPresented: $isAddingList) { ReminderListEditor(list: nil) }
        .sheet(item: $editingList) { ReminderListEditor(list: $0) }
        .alert("Couldn’t Save", isPresented: Binding(get: { model.reminders.errorMessage != nil },
                                                      set: { if !$0 { model.reminders.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.reminders.errorMessage ?? "")
        }
        .onAppear(perform: consumeRouterRequests)
        .onChange(of: model.router.isCreatingReminder) { consumeRouterRequests() }
        .onChange(of: model.router.pendingReminderID) { consumeRouterRequests() }
        .onChange(of: model.router.reminderListDeleted) { _, deleted in
            guard let deleted else { return }
            path.removeAll { $0 == .list(deleted) }
            model.router.reminderListDeleted = nil
        }
    }

    // MARK: Overview

    private var overview: some View {
        _ = model.clockEpoch
        let calendar = model.calendar
        let today = model.today
        func count(_ filter: ReminderFilter) -> Int { library.count(for: filter, today: today, calendar: calendar) }

        return ScrollView {
            VStack(alignment: .leading, spacing: RhythmSpacing.xl) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: RhythmSpacing.md), GridItem(.flexible())], spacing: RhythmSpacing.md) {
                    ForEach([ReminderFilter.today, .scheduled, .flagged, .all], id: \.self) { filter in
                        NavigationLink(value: filter) {
                            SmartListCard(filter: filter, count: count(filter))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("smartList-\(filter.title)")
                    }
                }

                NavigationLink(value: ReminderFilter.completed) {
                    HStack {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(library.reminders.filter(\.isCompleted).count)")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(RhythmSpacing.lg)
                    .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.row, style: .continuous))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: RhythmSpacing.sm) {
                    Text("My Lists")
                        .font(.title3.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        let lists = library.sortedLists
                        ForEach(lists) { list in
                            NavigationLink(value: ReminderFilter.list(list.id)) {
                                ListRow(list: list, count: count(.list(list.id)))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { editingList = list } label: { Label("Edit List", systemImage: "pencil") }
                                if lists.count > 1 {
                                    Button(role: .destructive) {
                                        model.reminders.deleteList(list.id)
                                    } label: {
                                        Label("Delete List", systemImage: "trash")
                                    }
                                }
                            }
                            if list.id != lists.last?.id { Divider().padding(.leading, 56) }
                        }
                    }
                    .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.row, style: .continuous))
                }
            }
            .padding(.horizontal, RhythmSpacing.lg)
            .padding(.top, RhythmSpacing.sm)
            .padding(.bottom, 96)
        }
    }

    private var searchResults: some View {
        let calendar = model.calendar
        let today = model.today
        let open = library.items(for: .all, today: today, calendar: calendar, search: search)
        let done = library.items(for: .completed, today: today, calendar: calendar, search: search)
        return Group {
            if open.isEmpty && done.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List {
                    if !open.isEmpty {
                        Section {
                            ForEach(open) { reminder in
                                ReminderRow(reminder: reminder, showsList: true) {
                                    editing = ReminderEditorTarget(reminder: reminder, isNew: false)
                                }
                            }
                        }
                    }
                    if !done.isEmpty {
                        Section("Completed") {
                            ForEach(done) { reminder in
                                ReminderRow(reminder: reminder, showsList: true) {
                                    editing = ReminderEditorTarget(reminder: reminder, isNew: false)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var newReminderButton: some View {
        Button(action: startNewReminder) {
            Label("New Reminder", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .padding(.horizontal, RhythmSpacing.xxl)
        .padding(.bottom, RhythmSpacing.sm)
        .accessibilityIdentifier("newReminderButton")
    }

    // MARK: Actions

    private func startNewReminder() {
        editing = ReminderEditorTarget(reminder: NativeReminder(title: "", listID: library.defaultListID), isNew: true)
    }

    /// Handles requests from deep links, widgets, and notifications.
    private func consumeRouterRequests() {
        let router = model.router
        if router.isCreatingReminder {
            router.isCreatingReminder = false
            path = []
            startNewReminder()
        }
        if let id = router.pendingReminderID {
            router.pendingReminderID = nil
            model.reminders.reload()
            if let reminder = library.reminder(id) {
                path = []
                editing = ReminderEditorTarget(reminder: reminder, isNew: false)
            }
        }
    }
}

private struct SmartListCard: View {
    let filter: ReminderFilter
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: RhythmSpacing.md) {
            HStack {
                Image(systemName: filter.symbolName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(filter.tint.gradient, in: Circle())
                    .accessibilityHidden(true)
                Spacer()
                Text("\(count)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
            }
            Text(filter.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(RhythmSpacing.md + 2)
        .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.row, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filter.title), \(count)")
    }
}

private struct ListRow: View {
    let list: NativeReminderList
    let count: Int

    var body: some View {
        HStack(spacing: RhythmSpacing.md) {
            Image(systemName: list.symbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(ReminderFormat.tint(forListKey: list.colorKey).gradient, in: Circle())
                .accessibilityHidden(true)
            Text(list.name)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, RhythmSpacing.lg)
        .padding(.vertical, RhythmSpacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
