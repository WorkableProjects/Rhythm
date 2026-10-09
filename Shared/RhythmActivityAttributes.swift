import ActivityKit
import Foundation

/// Live Activity attributes for the school day. Shared by the app (which starts, schedules,
/// updates, and ends the activity) and the widget extension (which renders it).
///
/// The content holds the current segment and the one after it. When the current segment ends,
/// the system marks the activity stale and re-renders it, and the view switches to the following
/// segment, so a passing period ("4:12 until Period 2") or the next period displays correctly even
/// if Rhythm isn't running. The payload stays far below ActivityKit's 4 KB limit.
struct RhythmActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        struct Segment: Codable, Hashable {
            enum Kind: String, Codable, Hashable {
                case period, passing, freeTime, beforeSchool
            }

            var kind: Kind
            /// The active period's title, or the title of the period being waited for.
            var title: String
            var symbolName: String
            var startDate: Date
            var endDate: Date
        }

        var current: Segment
        var following: Segment?
        /// Deep-link target (`rhythm://…`).
        var deepLink: URL
    }

    /// Name of the schedule in use, e.g. "Regular (Mon/Wed/Fri)".
    var scheduleName: String
}
