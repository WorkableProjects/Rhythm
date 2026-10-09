import RhythmCore
import SwiftData
import SwiftUI

/// Details for one period on one date, with quick routes to edit it everywhere or just for
/// that date.
struct PeriodDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let presentation: PeriodPresentation

    @State private var editingPeriod: PeriodEditTarget?
    @State private var isEditingDate = false

    var body: some View {
        NavigationStack {
            Group {
                if let resolved, let stored {
                    content(resolved: resolved, stored: stored)
                } else {
                    ContentUnavailableView(
                        "Period Not Found",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("This period was removed or isn’t on the schedule for this date.")
                    )
                }
            }
            .navigationTitle(resolved?.title ?? "Period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingPeriod) { target in
                PeriodEditorView(owner: target.owner, period: target.period)
            }
            .sheet(isPresented: $isEditingDate) {
                OverrideEditorView(date: presentation.date)
            }
        }
    }

    private var resolved: ResolvedPeriod? {
        model.resolvedDay(presentation.date).periods.first { $0.id == presentation.periodID }
    }

    private var stored: SchedulePeriod? {
        model.repository.period(id: presentation.periodID)
    }

    @ViewBuilder
    private func content(resolved: ResolvedPeriod, stored: SchedulePeriod) -> some View {
        List {
            Section {
                HStack(spacing: RhythmSpacing.md) {
                    PeriodSymbol(symbolName: resolved.symbolName, tint: RhythmPalette.tint(kind: resolved.kind, colorKey: resolved.colorKey), size: 44)
                    VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
                        Text(resolved.title).font(.title3.weight(.semibold))
                        Text(resolved.kind.displayName).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                LabeledContent("Date", value: presentation.date.formatted(in: model.calendar))
                LabeledContent("Time", value: "\(resolved.startDate.shortTime) – \(resolved.endDate.shortTime)")
                LabeledContent("Length", value: CountdownFormat.short(resolved.duration))
                if let detail = resolved.detail, !detail.isEmpty {
                    LabeledContent("Room or Teacher", value: detail)
                }
            }

            let reminders = stored.reminders.filter(\.isEnabled)
            if !reminders.isEmpty {
                Section("Reminders") {
                    ForEach(reminders) { rule in
                        LabeledContent(rule.title.isEmpty ? resolved.title : rule.title, value: rule.trigger?.displaySummary(calendar: model.calendar) ?? "")
                    }
                }
            }

            Section {
                Button {
                    editingPeriod = PeriodEditTarget(period: stored)
                } label: {
                    Label(editLabel(for: stored), systemImage: "pencil")
                }
                Button {
                    isEditingDate = true
                } label: {
                    Label("Change This Date Only", systemImage: "calendar.badge.clock")
                }
            } footer: {
                if stored.template != nil {
                    Text("Editing the period changes it on every day that uses this schedule.")
                }
            }
        }
    }

    private func editLabel(for period: SchedulePeriod) -> String {
        if let template = period.template { return "Edit in “\(template.name)”" }
        return "Edit Period"
    }
}

extension ReminderTrigger {
    /// Localized, user-facing description.
    func displaySummary(calendar: Calendar) -> String {
        switch self {
        case .beforeStart(let minutes) where minutes <= 0:
            return "At start"
        case .beforeStart(let minutes):
            return "\(minutes) min before start"
        case .oneOff(let date, let time):
            return "\(date.formatted(in: calendar, style: .dateTime.month(.abbreviated).day())), \(time.formatted(calendar: calendar))"
        }
    }
}
