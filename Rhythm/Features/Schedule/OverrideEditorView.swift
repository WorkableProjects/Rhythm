import RhythmCore
import SwiftData
import SwiftUI

/// Changes the schedule for one date only: no school, another template (late start, minimum
/// day), or custom one-off periods. Choosing "Regular Schedule" removes the change.
struct OverrideEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let date: LocalDate

    private enum Choice: Hashable {
        case regular, noSchool, special
    }

    /// `nil` means custom periods.
    @State private var basedOnTemplateID: UUID?
    @State private var choice: Choice = .regular
    @State private var title = ""
    @State private var didLoad = false
    @State private var editingPeriod: PeriodEditTarget?
    @State private var isAddingPeriod = false

    private var existing: ScheduleOverride? { model.repository.override(on: date) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("This Date", selection: $choice) {
                        Text("Regular").tag(Choice.regular)
                        Text("No School").tag(Choice.noSchool)
                        Text("Special").tag(Choice.special)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("overrideKindPicker")
                } header: {
                    Text(date.formatted(in: model.calendar))
                } footer: {
                    Text(footer)
                }

                if choice != .regular {
                    Section {
                        TextField(choice == .noSchool ? "Label, e.g. Holiday" : "Label, e.g. Assembly Day", text: $title)
                            .accessibilityIdentifier("overrideTitleField")
                    }
                }

                if choice == .special {
                    Section("Periods") {
                        Picker("Based On", selection: $basedOnTemplateID) {
                            ForEach(model.configuration.templates.values.sorted { $0.name < $1.name }) { template in
                                Text(template.name).tag(Optional(template.id))
                            }
                            Text("Custom Periods").tag(UUID?.none)
                        }
                        if basedOnTemplateID == nil {
                            customPeriods
                        }
                    }
                }
            }
            .navigationTitle("Change This Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if save() { dismiss() }
                    }
                    .accessibilityIdentifier("saveOverrideButton")
                }
            }
            .sheet(item: $editingPeriod) { target in
                PeriodEditorView(owner: target.owner, period: target.period)
            }
            .sheet(isPresented: $isAddingPeriod) {
                if let override = existing {
                    PeriodEditorView(owner: .dateOverride(override), period: nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private var customPeriods: some View {
        if let override = existing, override.kind == .customSchedule, override.templateID == nil {
            let periods = override.periods.sorted { ScheduleValidator.chronological($0.definition, $1.definition) }
            ForEach(periods) { period in
                Button {
                    editingPeriod = PeriodEditTarget(period: period)
                } label: {
                    LabeledContent(period.title) {
                        Text("\(period.start.formatted(calendar: model.calendar)) – \(period.end.formatted(calendar: model.calendar))")
                            .monospacedDigit()
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        model.commit { model.repository.deletePeriod(period) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Button {
                isAddingPeriod = true
            } label: {
                Label("Add Period", systemImage: "plus.circle")
            }
        } else {
            Text("Save to start from this day’s regular periods, then edit them here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Save and Edit Periods") { _ = save() }
                .accessibilityIdentifier("saveAndEditPeriodsButton")
        }
    }

    private var footer: String {
        switch choice {
        case .regular: "Uses the schedule normally assigned to this weekday."
        case .noSchool: "No periods or reminders on this date."
        case .special: "Use another schedule, like a late start, or set custom periods for this date only."
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let regularTemplateID = model.configuration.weekdayAssignments[date.weekday(in: model.calendar)]
        guard let existing else {
            basedOnTemplateID = regularTemplateID ?? model.configuration.templates.keys.first
            return
        }
        title = existing.title
        switch existing.kind {
        case .noSchool:
            choice = .noSchool
            basedOnTemplateID = regularTemplateID
        case .customSchedule:
            choice = .special
            basedOnTemplateID = existing.periods.isEmpty ? existing.templateID : nil
        }
    }

    /// Persists the current choice. Returns `true` on success.
    @discardableResult
    private func save() -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = model.repository
        switch choice {
        case .regular:
            guard let existing else { return true }
            return model.commit { repository.deleteOverride(existing) }
        case .noSchool:
            return model.commit { repository.setOverride(on: date, kind: .noSchool, title: trimmed, templateID: nil) }
        case .special:
            let templateID = basedOnTemplateID
            let regularPeriods = model.resolvedDay(date).periods
            let hadCustomPeriods = !(existing?.periods.isEmpty ?? true)
            return model.commit {
                let override = repository.setOverride(on: date, kind: .customSchedule, title: trimmed, templateID: templateID)
                if templateID != nil {
                    // Switching to a template replaces any custom periods.
                    override.periods.forEach { repository.deletePeriod($0) }
                } else if !hadCustomPeriods {
                    // Start custom periods from the day's regular schedule.
                    let sourcePeriods = regularPeriods.isEmpty
                        ? (model.configuration.templates.values.first?.periods ?? [])
                        : regularPeriods.compactMap { model.configuration.allPeriods[$0.id] }
                    for (index, period) in sourcePeriods.enumerated() {
                        var copy = period
                        copy.id = UUID()
                        copy.sortOrder = index
                        repository.upsertPeriod(copy, in: override)
                    }
                }
            }
        }
    }
}
