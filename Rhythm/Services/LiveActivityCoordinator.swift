import ActivityKit
import Foundation
import Observation
import RhythmCore

/// Runs Rhythm's Live Activity automatically, with no input from the user.
///
/// - **App opens or returns to the foreground** during school hours (from an hour before the first
///   bell to the last bell): the activity starts or updates immediately.
/// - **Before the first bell of the next school day:** an activity is scheduled with ActivityKit's
///   start date (iOS 26), so iOS starts it at that time even if Rhythm isn't running.
/// - **Bell to bell:** the content carries the current segment and the next one. When a segment
///   ends, iOS marks the activity stale and re-renders it, and the view shows the next segment
///   (e.g. "4:12 until Period 2"). While Rhythm runs (foreground, or a background refresh), it
///   updates the content at every bell.
///
/// Without a push server, iOS doesn't let an app change a Live Activity at exact times while it is
/// suspended; the stale-date handover and background refresh cover that as far as iOS allows.
@MainActor
@Observable
final class LiveActivityCoordinator {
    /// A short, user-facing description of the last failure, if any.
    private(set) var lastError: String?

    /// Whether iOS currently allows Rhythm's Live Activities.
    var systemAllowsActivities: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Activity id → the school day (`yyyy-MM-dd`) a scheduled activity was created for.
    private let defaults: UserDefaults
    private static let scheduledKey = "scheduledLiveActivities"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func reconcile(engine: ScheduleEngine, configuration: ScheduleConfiguration, now: Date, enabled: Bool) async {
        let activities = Activity<RhythmActivityAttributes>.activities
        guard enabled, systemAllowsActivities else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            scheduledDays = [:]
            return
        }

        let pending = activities.filter { $0.activityState == .pending }
        let running = activities.filter { $0.activityState == .active || $0.activityState == .stale }
        let today = engine.resolveDay(LocalDate(now, calendar: engine.calendar), configuration: configuration)

        if let frame = ScheduleSegments.liveFrame(at: now, day: today) {
            // A scheduled activity for today is redundant once the day is live.
            for activity in pending where scheduledDays[activity.id] == frame.date.key {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            await show(frame, source: today.source, running: running)
        } else {
            for activity in running { await activity.end(nil, dismissalPolicy: .immediate) }
        }

        await scheduleNextDay(engine: engine, configuration: configuration, now: now,
                              pending: Activity<RhythmActivityAttributes>.activities.filter { $0.activityState == .pending })
    }

    func endAll() async {
        for activity in Activity<RhythmActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        scheduledDays = [:]
    }

    // MARK: Showing and scheduling

    private func show(_ frame: LiveFrame, source: DaySource, running: [Activity<RhythmActivityAttributes>]) async {
        let state = Self.contentState(for: frame)
        let content = ActivityContent(state: state, staleDate: frame.current.endDate, relevanceScore: 100)
        if let current = running.first {
            for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            if current.content.state != state || current.activityState == .stale {
                await current.update(content)
            }
            return
        }
        do {
            let attributes = RhythmActivityAttributes(scheduleName: Self.scheduleName(for: source))
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            lastError = nil
        } catch {
            // Starting requires the foreground; a background refresh lands here harmlessly.
            lastError = "iOS didn’t start the Live Activity. Check that Live Activities are allowed for Rhythm in Settings."
        }
    }

    /// Keeps exactly one activity scheduled to start before the next school day's first bell.
    private func scheduleNextDay(engine: ScheduleEngine, configuration: ScheduleConfiguration, now: Date,
                                 pending: [Activity<RhythmActivityAttributes>]) async {
        guard let next = ScheduleSegments.nextAutomaticStart(after: now, engine: engine, configuration: configuration) else {
            for activity in pending { await activity.end(nil, dismissalPolicy: .immediate) }
            scheduledDays = [:]
            return
        }

        let key = next.date.key
        let state = Self.contentState(for: next)
        var keep: Activity<RhythmActivityAttributes>?
        for activity in pending {
            // Keep a matching schedule; replace it if the timetable changed since.
            if keep == nil, scheduledDays[activity.id] == key, activity.content.state == state {
                keep = activity
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        if let keep {
            scheduledDays = [keep.id: key]
            return
        }

        let day = engine.resolveDay(next.date, configuration: configuration)
        let firstPeriod = next.current.period
        do {
            let activity = try Activity.request(
                attributes: RhythmActivityAttributes(scheduleName: Self.scheduleName(for: day.source)),
                content: ActivityContent(state: state, staleDate: next.current.endDate, relevanceScore: 100),
                pushType: nil,
                style: .standard,
                alertConfiguration: AlertConfiguration(
                    title: "\(firstPeriod.title) starts at \(firstPeriod.startDate.formatted(date: .omitted, time: .shortened))",
                    body: "Rhythm will follow your day on the Lock Screen.",
                    sound: .default
                ),
                start: next.current.startDate
            )
            scheduledDays = [activity.id: key]
        } catch {
            // Scheduling isn't available (limits, settings, or background state). The activity
            // still starts the next time Rhythm opens during school hours.
            scheduledDays = [:]
        }
    }

    private var scheduledDays: [String: String] {
        get { defaults.dictionary(forKey: Self.scheduledKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Self.scheduledKey) }
    }

    // MARK: Mapping

    static func contentState(for frame: LiveFrame) -> RhythmActivityAttributes.ContentState {
        let deepLink = frame.current.kind == .period
            ? DeepLink.period(id: frame.current.period.id, date: frame.date).url
            : DeepLink.today(date: nil).url
        return .init(current: segment(frame.current), following: frame.following.map(segment), deepLink: deepLink)
    }

    private static func segment(_ segment: ScheduleSegment) -> RhythmActivityAttributes.ContentState.Segment {
        let kind: RhythmActivityAttributes.ContentState.Segment.Kind = switch segment.kind {
        case .period: .period
        case .passing: .passing
        case .freeTime: .freeTime
        case .beforeSchool: .beforeSchool
        }
        return .init(kind: kind, title: segment.period.title, symbolName: segment.period.symbolName,
                     startDate: segment.startDate, endDate: segment.endDate)
    }

    private static func scheduleName(for source: DaySource) -> String {
        switch source {
        case .template(_, let name): name
        case .customOverride(_, let title, _): title.isEmpty ? "Special Schedule" : title
        default: "Rhythm"
        }
    }
}
