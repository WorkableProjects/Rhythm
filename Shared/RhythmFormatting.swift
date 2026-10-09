import Foundation
import RhythmCore

// Display helpers shared by the app and the widget extension.

extension ClockTime {
    /// The time formatted for the user's locale and 12/24-hour preference.
    func formatted(calendar: Calendar = .autoupdatingCurrent) -> String {
        let reference = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour % 24, minute: minute)) ?? .now
        if minutesAfterMidnight >= ClockTime.endOfDayMinutes { return "Midnight" }
        return reference.formatted(date: .omitted, time: .shortened)
    }

    /// A `Date` on a fixed reference day, for binding to `DatePicker`.
    func referenceDate(calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: min(hour, 23), minute: hour >= 24 ? 59 : minute)) ?? .now
    }

    init(referenceDate: Date, calendar: Calendar = .autoupdatingCurrent) {
        let components = calendar.dateComponents([.hour, .minute], from: referenceDate)
        self.init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

extension LocalDate {
    /// A `Date` at local noon, safe for `DatePicker` bindings and display.
    func noon(in calendar: Calendar) -> Date {
        startDate(in: calendar).flatMap { calendar.date(byAdding: .hour, value: 12, to: $0) } ?? .now
    }

    func formatted(in calendar: Calendar, style: Date.FormatStyle = .dateTime.weekday(.wide).month(.wide).day()) -> String {
        noon(in: calendar).formatted(style)
    }
}
