import RhythmCore
import SwiftUI

/// One reminder in a list: a completion button, the title, and a line of details. Swipe and
/// long-press expose the common actions.
struct ReminderRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let reminder: NativeReminder
    var showsList = false
    var onOpen: () -> Void

    private var tint: Color {
        let list = model.reminders.library.list(reminder.listID)
        return ReminderFormat.tint(forListKey: list?.colorKey ?? "blue")
    }

    var body: some View {
        let calendar = model.calendar
        let now = model.now()
        let overdue = reminder.isOverdue(now: now, calendar: calendar)
        HStack(alignment: .top, spacing: RhythmSpacing.md) {
            Button {
                withAnimation(RhythmMotion.animation(RhythmMotion.stateChange, reduceMotion: reduceMotion)) {
                    model.reminders.toggle(reminder.id, now: now, calendar: calendar)
                }
            } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(reminder.isCompleted ? tint : (reminder.priority == .none ? Color.secondary : tint))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: RhythmLayout.minimumTouchTarget - RhythmSpacing.sm, height: RhythmLayout.minimumTouchTarget - RhythmSpacing.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: reminder.isCompleted)
            .accessibilityLabel(reminder.isCompleted ? "Mark \(reminder.title) incomplete" : "Complete \(reminder.title)")
            .accessibilityIdentifier("reminderCheckbox")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    titleLine
                    if !reminder.notes.isEmpty {
                        Text(reminder.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    detailLine(overdue: overdue, calendar: calendar)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, RhythmSpacing.xs)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                model.reminders.delete([reminder.id])
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                model.reminders.toggleFlag(reminder.id)
            } label: {
                Label(reminder.isFlagged ? "Unflag" : "Flag", systemImage: reminder.isFlagged ? "flag.slash" : "flag")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading) {
            if !reminder.isCompleted {
                Button {
                    snoozeToTomorrow(calendar: calendar)
                } label: {
                    Label("Tomorrow", systemImage: "arrow.uturn.forward")
                }
                .tint(.indigo)
            }
        }
        .contextMenu {
            Button { onOpen() } label: { Label("Edit", systemImage: "pencil") }
            Button { model.reminders.toggleFlag(reminder.id) } label: {
                Label(reminder.isFlagged ? "Remove Flag" : "Flag", systemImage: "flag")
            }
            if !reminder.isCompleted {
                Button { snoozeToTomorrow(calendar: calendar) } label: { Label("Move to Tomorrow", systemImage: "arrow.uturn.forward") }
            }
            Button(role: .destructive) { model.reminders.delete([reminder.id]) } label: { Label("Delete", systemImage: "trash") }
        }
        .accessibilityElement(children: .contain)
    }

    private var titleLine: some View {
        HStack(spacing: RhythmSpacing.xs) {
            if reminder.priority != .none {
                Text(reminder.priority.marks)
                    .font(.body.weight(.bold))
                    .foregroundStyle(tint)
                    .accessibilityLabel("\(reminder.priority.displayName) priority")
            }
            Text(reminder.title)
                .font(.body)
                .strikethrough(reminder.isCompleted)
                .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
            if reminder.isFlagged {
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Flagged")
            }
        }
    }

    @ViewBuilder
    private func detailLine(overdue: Bool, calendar: Calendar) -> some View {
        let due = ReminderFormat.dueText(reminder, today: model.today, calendar: calendar)
        let progress = reminder.subtaskProgress
        let hasDetails = due != nil || progress.total > 0 || reminder.repeatRule != .never || reminder.urlString != nil || showsList
        if hasDetails {
            HStack(spacing: RhythmSpacing.sm) {
                if let due {
                    Label(due, systemImage: overdue ? "exclamationmark.circle.fill" : "calendar")
                        .foregroundStyle(overdue ? Color.red : Color.secondary)
                }
                if reminder.repeatRule != .never {
                    Image(systemName: "repeat").accessibilityLabel(reminder.repeatRule.displayName)
                }
                if progress.total > 0 {
                    Label("\(progress.done)/\(progress.total)", systemImage: "checklist")
                }
                if reminder.urlString != nil {
                    Image(systemName: "link").accessibilityLabel("Has link")
                }
                if showsList, let list = model.reminders.library.list(reminder.listID) {
                    Text(list.name).foregroundStyle(tint)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(CompactLabelStyle())
        }
    }

    private func snoozeToTomorrow(calendar: Calendar) {
        let tomorrow = model.today.adding(days: 1, calendar: calendar)
        model.reminders.edit(requestingAuthorization: true) { $0.reschedule(reminder.id, to: tomorrow) }
    }
}

/// A label with a small gap between icon and title, used for metadata.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
