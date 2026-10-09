import ActivityKit
import Foundation

/// Live Activity attributes for the current period. Shared by the app (which starts, updates,
/// and ends the activity) and the widget extension (which renders it).
///
/// The content state is intentionally small and display-only; it stays well under ActivityKit's
/// 4 KB payload limit.
struct RhythmActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            /// A period is in progress; `startDate...endDate` is the period.
            case inPeriod
            /// Between periods; `startDate...endDate` runs until the next period starts.
            case freeTime
            /// Before the first period; `startDate...endDate` runs until it starts.
            case upcoming
        }

        var phase: Phase
        /// The active period's title, or the next period's title when not in a period.
        var title: String
        var kindName: String
        var symbolName: String
        var startDate: Date
        var endDate: Date
        var nextTitle: String?
        var nextStartDate: Date?
        /// Deep-link target (`rhythm://…`).
        var deepLink: URL
    }

    /// Name of the schedule in use, e.g. "Regular Day".
    var scheduleName: String
}
