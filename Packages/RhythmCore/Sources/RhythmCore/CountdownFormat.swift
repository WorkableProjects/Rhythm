import Foundation

/// Formatting for countdowns. Values are always derived from absolute dates by the caller.
public enum CountdownFormat {
    /// A compact clock-style value: `4:05`, `12:00`, or `1:02:03`. Seconds are rounded up so a
    /// countdown never shows `0:00` while time remains.
    public static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// A short, minute-precision description such as `1 hr 5 min` or `under 1 min`, used
    /// where a ticking value would be distracting (rows, widgets' secondary text).
    public static func short(_ interval: TimeInterval) -> String {
        let minutes = Int((max(0, interval) / 60).rounded(.up))
        if interval <= 0 { return "0 min" }
        if minutes < 1 { return "under 1 min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        switch (hours, remainder) {
        case (0, _): return "\(minutes) min"
        case (_, 0): return "\(hours) hr"
        default: return "\(hours) hr \(remainder) min"
        }
    }

    /// A VoiceOver-friendly phrase such as "12 minutes" or "1 hour, 5 minutes". Uses minute
    /// precision (rounded up) because announcing seconds is noisy.
    public static func spoken(_ interval: TimeInterval) -> String {
        let minutes = Int((max(0, interval) / 60).rounded(.up))
        if minutes <= 0 { return "less than a minute" }
        let hours = minutes / 60
        let remainder = minutes % 60
        func unit(_ value: Int, _ singular: String) -> String { "\(value) \(singular)\(value == 1 ? "" : "s")" }
        switch (hours, remainder) {
        case (0, _): return unit(minutes, "minute")
        case (_, 0): return unit(hours, "hour")
        default: return "\(unit(hours, "hour")), \(unit(remainder, "minute"))"
        }
    }
}
