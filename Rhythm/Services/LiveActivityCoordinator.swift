import ActivityKit
import Foundation
import Observation
import RhythmCore

/// Starts, updates, and ends Rhythm's single Live Activity to match the schedule.
///
/// The activity's countdown is rendered by the system from absolute dates, so Rhythm never
/// pushes per-second updates. Without a push server, content can only change while Rhythm runs;
/// each update sets a stale date at the next boundary so the Lock Screen can show "up next"
/// instead of a misleading finished timer.
@MainActor
@Observable
final class LiveActivityCoordinator {
    /// A short, user-facing description of the last failure, if any.
    private(set) var lastError: String?

    /// Whether iOS currently allows Rhythm's Live Activities.
    var systemAllowsActivities: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Show an activity from this long before the first period of the day.
    static let upcomingLeadTime: TimeInterval = 60 * 60

    func reconcile(snapshot: ScheduleSnapshot, enabled: Bool) async {
        let activities = Activity<RhythmActivityAttributes>.activities
        guard enabled, systemAllowsActivities, let state = Self.contentState(for: snapshot) else {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let content = ActivityContent(state: state, staleDate: state.endDate, relevanceScore: 100)
        if let current = activities.first {
            for extra in activities.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            if current.content.state != state {
                await current.update(content)
            }
        } else {
            do {
                let attributes = RhythmActivityAttributes(scheduleName: Self.scheduleName(for: snapshot.day.source))
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                lastError = nil
            } catch {
                // Activity limits, disabled settings, or unsupported devices: Rhythm keeps working.
                lastError = "iOS didn’t start the Live Activity. Check that Live Activities are allowed for Rhythm in Settings."
            }
        }
    }

    func endAll() async {
        for activity in Activity<RhythmActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Maps the live schedule to activity content, or `nil` when no activity should be shown.
    static func contentState(for snapshot: ScheduleSnapshot) -> RhythmActivityAttributes.ContentState? {
        let date = snapshot.day.date
        switch snapshot.state {
        case .inProgress:
            guard let active = snapshot.activePeriod else { return nil }
            return .init(phase: .inPeriod, title: active.title, kindName: active.kind.displayName, symbolName: active.symbolName,
                         startDate: active.startDate, endDate: active.endDate,
                         nextTitle: snapshot.nextPeriod?.title, nextStartDate: snapshot.nextPeriod?.startDate,
                         deepLink: DeepLink.period(id: active.id, date: date).url)
        case .freeTime:
            guard let next = snapshot.nextPeriod, let previous = snapshot.previousPeriod else { return nil }
            return .init(phase: .freeTime, title: next.title, kindName: next.kind.displayName, symbolName: next.symbolName,
                         startDate: previous.endDate, endDate: next.startDate,
                         nextTitle: next.title, nextStartDate: next.startDate,
                         deepLink: DeepLink.today(date: nil).url)
        case .upcoming:
            guard let next = snapshot.nextPeriod,
                  next.startDate.timeIntervalSince(snapshot.now) <= upcomingLeadTime else { return nil }
            return .init(phase: .upcoming, title: next.title, kindName: next.kind.displayName, symbolName: next.symbolName,
                         startDate: snapshot.now, endDate: next.startDate,
                         nextTitle: next.title, nextStartDate: next.startDate,
                         deepLink: DeepLink.today(date: nil).url)
        case .scheduleNeeded, .noSchool, .dayComplete:
            return nil
        }
    }

    private static func scheduleName(for source: DaySource) -> String {
        switch source {
        case .template(_, let name): name
        case .customOverride(_, let title, _): title.isEmpty ? "Special Schedule" : title
        default: "Rhythm"
        }
    }
}
