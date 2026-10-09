import RhythmCore
import SwiftUI

/// The category symbol for a period on a tinted, rounded background. Decorative: the
/// accompanying text always states the category, so VoiceOver skips the symbol.
struct PeriodSymbol: View {
    var symbolName: String
    var tint: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: RhythmRadius.control, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A small capsule tag used for semantic labels such as "Now" or "Sample".
struct TagLabel: View {
    var text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, RhythmSpacing.sm)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

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
