import RhythmCore
import SwiftUI

/// Native reminders that are overdue or due today, with a checkmark on each. Renders nothing when
/// there are none, so no empty card takes up space.
struct DueTodayCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let calendar = model.calendar
        let today = model.today
        let all = model.reminders.library.items(for: .today, today: today, calendar: calendar)
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: RhythmSpacing.sm) {
                HStack {
                    Text("Due Today")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("See All") {
                        model.router.selectedTab = .reminders
                    }
                    .font(.subheadline)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(all.prefix(4)) { reminder in
                        let overdue = reminder.isOverdue(now: model.now(), calendar: calendar)
                        HStack(spacing: RhythmSpacing.md) {
                            Button {
                                model.reminders.toggle(reminder.id, now: model.now(), calendar: calendar)
                            } label: {
                                Image(systemName: "circle")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: RhythmLayout.minimumTouchTarget, height: RhythmLayout.minimumTouchTarget)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Complete \(reminder.title)")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.title).font(.subheadline.weight(.semibold))
                                if let due = ReminderFormat.dueText(reminder, today: today, calendar: calendar) {
                                    Text(due)
                                        .font(.caption)
                                        .foregroundStyle(overdue ? Color.red : Color.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if all.count > 4 {
                        Text("+\(all.count - 4) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, RhythmSpacing.sm)
                            .padding(.leading, RhythmSpacing.lg)
                    }
                }
                .padding(.horizontal, RhythmSpacing.xs)
                .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.row, style: .continuous))
            }
        }
    }
}
