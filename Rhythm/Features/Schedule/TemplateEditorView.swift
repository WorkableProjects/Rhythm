import RhythmCore
import SwiftData
import SwiftUI

/// Edits a schedule template: its name, weekdays, and ordered periods. Deleting a period offers
/// an Undo for a few seconds.
struct TemplateEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var template: ScheduleTemplate

    @State private var editingPeriod: SchedulePeriod?
    @State private var isAddingPeriod = false
    @State private var recentlyDeleted: DeletedPeriod?
    @State private var isConfirmingDelete = false

    /// Everything needed to restore a deleted period.
    private struct DeletedPeriod: Equatable {
        var definition: PeriodDefinition
        var reminders: [ReminderDefinition]
    }

    var body: some View {
        List {
            Section("Name") {
                TextField("Schedule name", text: $template.name)
                    .onSubmit { model.commit() }
                    .accessibilityIdentifier("templateNameField")
            }

            Section {
                WeekdayChips(templateID: template.id)
            } header: {
                Text("Days")
            } footer: {
                Text("Choosing a day here moves it from any other schedule.")
            }

            periodsSection

            let issues = ScheduleValidator.validate(periods: template.periods.map(\.definition))
            if !issues.isEmpty {
                Section("Needs Attention") {
                    ForEach(issues) { issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                Button("Duplicate Schedule") {
                    model.commit { model.repository.duplicateTemplate(template) }
                }
                Button("Delete Schedule", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .navigationTitle(template.name.isEmpty ? "Schedule" : template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingPeriod = true
                } label: {
                    Label("Add Period", systemImage: "plus")
                }
                .accessibilityIdentifier("addPeriodButton")
            }
        }
        .onDisappear {
            if !template.isDeleted { model.commit() }
        }
        .sheet(item: $editingPeriod) { period in
            PeriodEditorView(owner: .template(template), period: period)
        }
        .sheet(isPresented: $isAddingPeriod) {
            PeriodEditorView(owner: .template(template), period: nil)
        }
        .confirmationDialog("Delete “\(template.name)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Schedule", role: .destructive) {
                // Leave the screen before deleting so no view reads a deleted model.
                let template = template
                let model = model
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    model.commit { model.repository.deleteTemplate(template) }
                }
            }
        } message: {
            Text("Its periods and reminders will be removed, and its days will have no schedule.")
        }
        .safeAreaInset(edge: .bottom) {
            if let recentlyDeleted {
                UndoBar(title: recentlyDeleted.definition.title) { restore(recentlyDeleted) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(RhythmMotion.animation(RhythmMotion.stateChange, reduceMotion: reduceMotion), value: recentlyDeleted)
        .task(id: recentlyDeleted) {
            guard recentlyDeleted != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { recentlyDeleted = nil }
        }
    }

    private var periodsSection: some View {
        Section {
            if template.periods.isEmpty {
                Text("No periods yet. Add your first class, lunch, or break.")
                    .foregroundStyle(.secondary)
            }
            ForEach(template.sortedPeriods) { period in
                Button {
                    editingPeriod = period
                } label: {
                    TemplatePeriodRow(period: period)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) { delete(period) } label: { Label("Delete", systemImage: "trash") }
                }
                .contextMenu {
                    Button("Edit") { editingPeriod = period }
                    Button("Delete", role: .destructive) { delete(period) }
                }
                .accessibilityIdentifier("templatePeriodRow-\(period.title)")
            }
            Button {
                isAddingPeriod = true
            } label: {
                Label("Add Period", systemImage: "plus.circle")
            }
        } header: {
            Text("Periods")
        } footer: {
            if let first = template.sortedPeriods.first(where: \.isEnabled), let last = template.sortedPeriods.last(where: \.isEnabled) {
                Text("\(template.periods.count) periods, \(first.start.formatted(calendar: model.calendar)) – \(last.end.formatted(calendar: model.calendar)).")
            }
        }
    }

    private func delete(_ period: SchedulePeriod) {
        let backup = DeletedPeriod(definition: period.definition, reminders: period.reminders.compactMap(\.definition))
        if model.commit({ model.repository.deletePeriod(period) }) {
            recentlyDeleted = backup
        }
    }

    private func restore(_ backup: DeletedPeriod) {
        model.commit {
            let restored = model.repository.upsertPeriod(backup.definition, in: template)
            model.repository.setReminders(backup.reminders, for: restored)
        }
        recentlyDeleted = nil
    }
}

private struct TemplatePeriodRow: View {
    @Environment(AppModel.self) private var model
    let period: SchedulePeriod

    var body: some View {
        HStack(spacing: RhythmSpacing.md) {
            PeriodSymbol(symbolName: period.symbolName ?? period.kind.defaultSymbolName,
                         tint: RhythmPalette.tint(kind: period.kind, colorKey: period.colorKey))
            VStack(alignment: .leading, spacing: 2) {
                Text(period.title.isEmpty ? "Untitled" : period.title)
                    .foregroundStyle(period.isEnabled ? .primary : .secondary)
                Text("\(period.start.formatted(calendar: model.calendar)) – \(period.end.formatted(calendar: model.calendar)) · \(period.kind.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if !period.reminders.isEmpty {
                Image(systemName: "bell")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Has reminders")
            }
            if !period.isEnabled {
                TagLabel(text: "Off")
            }
        }
        .contentShape(Rectangle())
        .frame(minHeight: RhythmLayout.minimumTouchTarget)
        .accessibilityElement(children: .combine)
    }
}

/// Toggle chips assigning this template to weekdays.
struct WeekdayChips: View {
    @Environment(AppModel.self) private var model
    let templateID: UUID

    var body: some View {
        let calendar = model.calendar
        HStack(spacing: RhythmSpacing.xs) {
            ForEach(Weekday.ordered(for: calendar)) { weekday in
                let isOn = model.configuration.weekdayAssignments[weekday] == templateID
                Button {
                    model.commit { model.repository.assign(weekday, to: isOn ? nil : templateID) }
                } label: {
                    Text(weekday.shortName(in: calendar))
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: RhythmLayout.minimumTouchTarget)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: RhythmRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weekday.name(in: calendar))
                .accessibilityValue(isOn ? "Selected" : "Not selected")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// A floating Undo control. Floats over content, so it uses the Liquid Glass control layer.
struct UndoBar: View {
    let title: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: RhythmSpacing.md) {
            Text("Deleted “\(title.isEmpty ? "period" : title)”")
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: RhythmSpacing.sm)
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("undoDeleteButton")
        }
        .padding(.horizontal, RhythmSpacing.xl)
        .frame(minHeight: RhythmLayout.minimumTouchTarget + RhythmSpacing.sm)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, RhythmSpacing.lg)
        .padding(.bottom, RhythmSpacing.sm)
    }
}
