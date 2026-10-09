import RhythmCore
import SwiftData
import SwiftUI

/// A compact list of today's remaining reminders. Renders nothing when there are none, so no
/// empty card takes up space.
struct TodayRemindersView: View {
    @Environment(AppModel.self) private var model
    @Query private var rules: [ReminderRule]
    let day: ResolvedDay
    let now: Date

    init(day: ResolvedDay, now: Date) {
        self.day = day
        self.now = now
        _rules = Query(filter: #Predicate<ReminderRule> { $0.isEnabled })
    }

    private struct Item: Identifiable {
        var id: UUID
        var title: String
        var periodTitle: String
        var fireDate: Date
    }

    private var items: [Item] {
        let periods = Dictionary(day.periods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return rules.compactMap { rule -> Item? in
            guard let periodID = rule.period?.id, let period = periods[periodID], let trigger = rule.trigger else { return nil }
            let fireDate: Date?
            switch trigger {
            case .beforeStart(let minutes):
                fireDate = period.startDate.addingTimeInterval(-TimeInterval(minutes * 60))
            case .oneOff(let date, let time):
                fireDate = date == day.date ? date.date(at: time, in: model.calendar) : nil
            }
            guard let fireDate, period.endDate > now else { return nil }
            let title = rule.title.isEmpty ? period.title : rule.title
            return Item(id: rule.id, title: title, periodTitle: period.title, fireDate: fireDate)
        }
        .sorted { $0.fireDate < $1.fireDate }
    }

    private var activeRules: [ReminderRule] {
        rules.filter { $0.status == .active }
    }

    var body: some View {
        let active = activeRules
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: RhythmSpacing.sm) {
                HStack {
                    Text("Reminders")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("See All") {
                        model.router.selectedTab = .reminders
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: RhythmSpacing.md) {
                    ForEach(active.prefix(5)) { rule in
                        HStack(spacing: RhythmSpacing.md) {
                            Button {
                                withAnimation {
                                    model.commit {
                                        model.repository.setReminderStatus(rule, status: .completed)
                                    }
                                }
                            } label: {
                                Image(systemName: "circle")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.title)
                                    .font(.subheadline.weight(.semibold))
                                if let period = rule.period {
                                    Text(period.title)
                                        .font(.caption)
                                        .foregroundStyle(.tint)
                                } else if let date = rule.dueDate {
                                    Text(date.key)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 0)

                            Menu {
                                Button("Snooze 15m") {
                                    model.commit {
                                        let snoozedUntil = Date.now.addingTimeInterval(15 * 60)
                                        model.repository.setReminderStatus(rule, status: .snoozed, snoozedUntil: snoozedUntil)
                                    }
                                }
                                Button("Mark Complete") {
                                    model.commit {
                                        model.repository.setReminderStatus(rule, status: .completed)
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(RhythmSpacing.lg)
                .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.row, style: .continuous))
            }
        }
    }
}
