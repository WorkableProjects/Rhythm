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

    var body: some View {
        let items = items
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: RhythmSpacing.sm) {
                Text("Period Reminders")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: RhythmSpacing.md) {
                    ForEach(items.prefix(4)) { item in
                        HStack(spacing: RhythmSpacing.md) {
                            Image(systemName: "bell")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.periodTitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Text(item.fireDate.shortTime)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(RhythmSpacing.lg)
                .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.row, style: .continuous))
            }
        }
    }
}
