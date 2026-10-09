import RhythmCore
import SwiftUI

/// Display helpers for native reminders.
enum ReminderFormat {
    /// "Today", "Tomorrow", a weekday for the next week, otherwise a short date.
    static func dayName(_ date: LocalDate, today: LocalDate, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: today.noon(in: calendar), to: date.noon(in: calendar)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return date.weekday(in: calendar).name(in: calendar)
        default:
            let style: Date.FormatStyle = date.year == today.year
                ? .dateTime.month(.abbreviated).day()
                : .dateTime.month(.abbreviated).day().year()
            return date.formatted(in: calendar, style: style)
        }
    }

    /// "Tomorrow, 3:00 PM", "Fri", or `nil` when there's no due date.
    static func dueText(_ reminder: NativeReminder, today: LocalDate, calendar: Calendar) -> String? {
        guard let date = reminder.dueDate else { return nil }
        let day = dayName(date, today: today, calendar: calendar)
        guard let time = reminder.dueTime else { return day }
        return "\(day), \(time.formatted(calendar: calendar))"
    }

    static func title(for bucket: ReminderBucket, calendar: Calendar) -> String {
        switch bucket {
        case .overdue: "Overdue"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .upcoming(let date): date.formatted(in: calendar, style: .dateTime.weekday(.wide).month(.abbreviated).day())
        case .noDate: "No Date"
        }
    }

    static func alertText(minutes: Int) -> String {
        switch minutes {
        case 0: "At time of event"
        case 60: "1 hour before"
        case 120: "2 hours before"
        case 1440: "1 day before"
        default: "\(minutes) minutes before"
        }
    }

    static let alertChoices = [0, 5, 10, 15, 30, 60, 120, 1440]

    static func tint(forListKey key: String) -> Color {
        RhythmPalette.color(forKey: key) ?? .blue
    }
}

extension ReminderFilter {
    var title: String {
        switch self {
        case .today: "Today"
        case .scheduled: "Scheduled"
        case .flagged: "Flagged"
        case .all: "All"
        case .completed: "Completed"
        case .list: "List"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "sun.max.fill"
        case .scheduled: "calendar"
        case .flagged: "flag.fill"
        case .all: "tray.fill"
        case .completed: "checkmark.circle.fill"
        case .list: "list.bullet"
        }
    }

    var tint: Color {
        switch self {
        case .today: .blue
        case .scheduled: .red
        case .flagged: .orange
        case .all: .indigo
        case .completed: .gray
        case .list: .blue
        }
    }
}
