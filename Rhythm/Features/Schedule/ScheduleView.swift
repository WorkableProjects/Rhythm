import RhythmCore
import SwiftData
import SwiftUI

/// The Schedule tab: a day preview with "change this date only", templates, the weekly pattern,
/// and upcoming date changes.
struct ScheduleView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \ScheduleTemplate.createdAt) private var templates: [ScheduleTemplate]
    @Query(sort: \ScheduleOverride.dateKey) private var overrides: [ScheduleOverride]

    @State private var openedTemplate: ScheduleTemplate?
    @State private var editingOverrideDate: LocalDate?
    @State private var templatePendingDeletion: ScheduleTemplate?

    var body: some View {
        @Bindable var router = model.router
        NavigationStack {
            List {
                DaySection(date: router.scheduleDate ?? model.today) { editingOverrideDate = $0 }
                templatesSection
                if !templates.isEmpty {
                    weekSection
                }
                overridesSection
                BellScheduleSection()
            }
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        router.isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            router.isCreatingTemplate = true
                        } label: {
                            Label("New Schedule", systemImage: "calendar.badge.plus")
                        }
                        .accessibilityIdentifier("newScheduleMenuItem")
                        Button {
                            editingOverrideDate = router.scheduleDate ?? model.today
                        } label: {
                            Label("Change a Date", systemImage: "calendar.badge.clock")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .accessibilityIdentifier("scheduleAddMenu")
                }
            }
            .navigationDestination(for: BellSchedulePreset.Kind.self) { kind in
                BellScheduleDetailView(kind: kind)
            }
            .navigationDestination(for: ScheduleTemplate.self) { template in
                TemplateEditorView(template: template)
            }
            .navigationDestination(item: $openedTemplate) { template in
                TemplateEditorView(template: template)
            }
            .sheet(isPresented: $router.isCreatingTemplate) {
                NewTemplateSheet { created in openedTemplate = created }
            }
            .sheet(item: Binding(
                get: { editingOverrideDate.map(IdentifiedDate.init) },
                set: { editingOverrideDate = $0?.date }
            )) { item in
                OverrideEditorView(date: item.date)
            }
            .confirmationDialog(
                "Delete “\(templatePendingDeletion?.name ?? "")”?",
                isPresented: Binding(get: { templatePendingDeletion != nil }, set: { if !$0 { templatePendingDeletion = nil } }),
                titleVisibility: .visible,
                presenting: templatePendingDeletion
            ) { template in
                Button("Delete Schedule", role: .destructive) {
                    model.commit { model.repository.deleteTemplate(template) }
                }
            } message: { _ in
                Text("Its periods and reminders will be removed, and its days will have no schedule.")
            }
            .task(id: router.pendingTemplateID) {
                // Set by onboarding to open a newly created schedule.
                guard let id = router.pendingTemplateID else { return }
                openedTemplate = model.repository.template(id: id)
                router.pendingTemplateID = nil
            }
        }
    }

    private var templatesSection: some View {
        Section {
            if templates.isEmpty {
                Button {
                    model.router.isCreatingTemplate = true
                } label: {
                    Label("Create Your First Schedule", systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("createFirstScheduleButton")
            }
            ForEach(templates) { template in
                NavigationLink(value: template) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(template.name)
                            if template.isSample { TagLabel(text: "Sample") }
                        }
                        Text(summary(for: template))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { templatePendingDeletion = template } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button("Duplicate") { model.commit { model.repository.duplicateTemplate(template) } }
                    Button("Delete", role: .destructive) { templatePendingDeletion = template }
                }
                .accessibilityIdentifier("templateRow-\(template.name)")
            }
        } header: {
            Text("My Schedules")
        } footer: {
            Text("A schedule is one full day of periods. Several weekdays can share it.")
        }
    }

    private var weekSection: some View {
        Section("Week") {
            let calendar = model.calendar
            ForEach(Weekday.ordered(for: calendar)) { weekday in
                Picker(weekday.name(in: calendar), selection: Binding<UUID?>(
                    get: { model.configuration.weekdayAssignments[weekday] },
                    set: { newValue in model.commit { model.repository.assign(weekday, to: newValue) } }
                )) {
                    Text("No School").tag(UUID?.none)
                    ForEach(templates) { template in
                        Text(template.name).tag(Optional(template.id))
                    }
                }
                .accessibilityIdentifier("weekdayPicker-\(weekday.rawValue)")
            }
        }
    }

    private var overridesSection: some View {
        let today = model.today
        let upcoming = overrides.filter { ($0.date ?? today) >= today }
        return Section {
            ForEach(upcoming) { override in
                Button {
                    editingOverrideDate = override.date
                } label: {
                    LabeledContent {
                        Text(override.kind.displayName)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(override.date?.formatted(in: model.calendar) ?? override.dateKey)
                                .foregroundStyle(.primary)
                            if !override.title.isEmpty {
                                Text(override.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        model.commit { model.repository.deleteOverride(override) }
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                }
            }
            Button {
                editingOverrideDate = model.router.scheduleDate ?? today
            } label: {
                Label("Change a Date", systemImage: "calendar.badge.clock")
            }
        } header: {
            Text("Date Changes")
        } footer: {
            Text("Mark holidays, assemblies, late starts, or minimum days without changing your regular week.")
        }
    }

    private func summary(for template: ScheduleTemplate) -> String {
        let calendar = model.calendar
        let days = model.repository.weekdays(assignedTo: template.id).map { $0.shortName(in: calendar) }
        let count = template.periods.count
        let periods = "\(count) \(count == 1 ? "period" : "periods")"
        return days.isEmpty ? "\(periods) · Not assigned" : "\(periods) · \(days.joined(separator: ", "))"
    }
}

/// A `LocalDate` wrapper usable with `sheet(item:)`.
struct IdentifiedDate: Identifiable {
    var date: LocalDate
    var id: String { date.key }
}

/// Preview of one date's resolved schedule with date navigation.
private struct DaySection: View {
    @Environment(AppModel.self) private var model
    let date: LocalDate
    let onChangeDate: (LocalDate) -> Void

    var body: some View {
        let calendar = model.calendar
        let day = model.resolvedDay(date)
        Section {
            DatePicker("Date", selection: Binding(
                get: { date.noon(in: calendar) },
                set: { model.router.scheduleDate = LocalDate($0, calendar: calendar) }
            ), displayedComponents: .date)

            LabeledContent("Schedule", value: sourceDescription(day.source))

            ForEach(day.periods) { period in
                HStack {
                    Image(systemName: period.symbolName)
                        .foregroundStyle(RhythmPalette.tint(kind: period.kind, colorKey: period.colorKey))
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(period.title)
                    Spacer()
                    Text("\(period.startDate.shortTime) – \(period.endDate.shortTime)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }

            if model.configuration.hasAnySchedule {
                Button {
                    onChangeDate(date)
                } label: {
                    Label("Change This Date Only", systemImage: "calendar.badge.clock")
                }
                .accessibilityIdentifier("changeThisDateButton")
            }
        } header: {
            Text(date == model.today ? "Today" : date.formatted(in: calendar, style: .dateTime.weekday(.wide)))
        }
    }

    private func sourceDescription(_ source: DaySource) -> String {
        switch source {
        case .noScheduleConfigured: "None yet"
        case .unassigned: "No School"
        case .template(_, let name): name
        case .noSchoolOverride(_, let title): title.isEmpty ? "No School" : "No School · \(title)"
        case .customOverride(_, let title, _): title.isEmpty ? "Special Schedule" : title
        }
    }
}
