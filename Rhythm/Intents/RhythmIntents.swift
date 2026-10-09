import AppIntents
import Foundation
import RhythmCore

// Rhythm's own actions for the Shortcuts app and Siri, built on the public App Intents
// framework. Rhythm can expose these actions and open user-provided Shortcut URLs; it cannot
// list, inspect, or silently run other shortcuts.

/// Opens Rhythm to today's live schedule.
struct ShowTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Today in Rhythm"
    static let description = IntentDescription("Opens Rhythm to today’s schedule.")
    static let openAppWhenRun = true

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        model.router.handle(.today(date: nil))
        return .result()
    }
}

/// Returns the period in progress, or describes free time / no school.
struct GetCurrentPeriodIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Period"
    static let description = IntentDescription(
        "Returns the name of the period in progress in Rhythm. If no period is in progress, returns the current state, such as Free Time or No School."
    )

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let snapshot = model.snapshot()
        let value: String
        let sentence: String
        switch snapshot.state {
        case .inProgress:
            let active = snapshot.activePeriod!
            value = active.title
            sentence = "\(active.title) is in progress, with \(CountdownFormat.spoken(active.remaining(at: snapshot.now))) left. It ends at \(active.endDate.shortTime)."
        case .freeTime, .upcoming:
            value = snapshot.state.displayName
            if let next = snapshot.nextPeriod {
                sentence = "No period right now. \(next.title) starts at \(next.startDate.shortTime)."
            } else {
                sentence = "No period right now."
            }
        case .dayComplete:
            value = snapshot.state.displayName
            sentence = "All periods have ended for today."
        case .noSchool:
            value = snapshot.state.displayName
            sentence = "There’s no school today."
        case .scheduleNeeded:
            value = snapshot.state.displayName
            sentence = "You haven’t set up a schedule in Rhythm yet."
        }
        return .result(value: value, dialog: "\(sentence)")
    }
}

/// Returns the next period, looking ahead to later days when today is finished.
struct GetNextPeriodIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Next Period"
    static let description = IntentDescription("Returns the name and start time of your next period in Rhythm.")

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let now = model.now()
        guard let next = model.engine.nextPeriod(after: now, configuration: model.configuration) else {
            let message = model.configuration.hasAnySchedule
                ? "There are no periods in the next two weeks."
                : "You haven’t set up a schedule in Rhythm yet."
            return .result(value: "", dialog: "\(message)")
        }
        let isToday = next.day.date == LocalDate(now, calendar: model.calendar)
        let when = isToday
            ? "at \(next.period.startDate.shortTime)"
            : "\(next.day.date.formatted(in: model.calendar, style: .dateTime.weekday(.wide))) at \(next.period.startDate.shortTime)"
        return .result(value: next.period.title, dialog: "\(next.period.title) starts \(when).")
    }
}

/// Starts or updates Rhythm's Live Activity. As a `LiveActivityIntent`, iOS lets it start the
/// activity even while Rhythm is in the background, so a Shortcuts automation (for example, every
/// school day at 8:00 AM, "Run Immediately") brings it up with no taps.
struct StartLiveActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Rhythm Live Activity"
    static let description = IntentDescription(
        "Shows your current or next period on the Lock Screen and in the Dynamic Island. Add it to a Shortcuts time-of-day automation so it starts on its own each school day."
    )

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        await model.startLiveActivityNow()
        return .result()
    }
}

/// Recomputes schedule state and refreshes widgets, reminders, and the Live Activity locally.
struct RefreshScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Rhythm Schedule"
    static let description = IntentDescription("Recalculates your schedule and updates Rhythm’s widgets, reminders, and Live Activity. Works offline.")

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        model.reload()
        model.refreshIntegrations()
        return .result(dialog: "Rhythm is up to date.")
    }
}

/// Opens one of the user's Quicklinks through the system URL-opening action.
struct OpenQuicklinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quicklink"
    static let description = IntentDescription("Opens one of your Rhythm Quicklinks: a website, app link, or Shortcut link.")

    @Parameter(title: "Quicklink")
    var quicklink: QuicklinkEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        guard case .success(let validated) = QuicklinkURLValidator.validate(quicklink.urlString) else {
            throw RhythmIntentError.invalidLink(quicklink.title)
        }
        return .result(opensIntent: OpenURLIntent(validated.url))
    }
}

/// A user-owned Quicklink exposed to Shortcuts.
struct QuicklinkEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Quicklink"
    static var defaultQuery: QuicklinkQuery { QuicklinkQuery() }

    let id: UUID
    let title: String
    let urlString: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct QuicklinkQuery: EntityQuery {
    @Dependency private var model: AppModel

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [QuicklinkEntity] {
        let wanted = Set(identifiers)
        return model.repository.quicklinks().filter { wanted.contains($0.id) }.map { QuicklinkEntity($0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [QuicklinkEntity] {
        model.repository.quicklinks().map { QuicklinkEntity($0) }
    }
}

extension QuicklinkEntity {
    @MainActor
    init(_ link: Quicklink) {
        self.init(id: link.id, title: link.title, urlString: link.urlString)
    }
}

enum RhythmIntentError: Error, CustomLocalizedStringResourceConvertible {
    case invalidLink(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidLink(let title):
            "“\(title)” doesn’t have a valid link. Edit it in Rhythm."
        }
    }
}

/// Suggested phrases for Siri and Spotlight. Every phrase includes the app name, as required.
struct RhythmAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetCurrentPeriodIntent(),
            phrases: [
                "What period is it in \(.applicationName)",
                "What class am I in with \(.applicationName)"
            ],
            shortTitle: "Current Period",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: GetNextPeriodIntent(),
            phrases: [
                "What’s next in \(.applicationName)",
                "What’s my next class in \(.applicationName)"
            ],
            shortTitle: "Next Period",
            systemImageName: "forward"
        )
        AppShortcut(
            intent: ShowTodayIntent(),
            phrases: ["Show today in \(.applicationName)"],
            shortTitle: "Show Today",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: OpenQuicklinkIntent(),
            phrases: ["Open a Quicklink in \(.applicationName)"],
            shortTitle: "Open Quicklink",
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: StartLiveActivityIntent(),
            phrases: ["Start \(.applicationName) Live Activity", "Show my day in \(.applicationName)"],
            shortTitle: "Start Live Activity",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: RefreshScheduleIntent(),
            phrases: ["Refresh \(.applicationName)"],
            shortTitle: "Refresh Schedule",
            systemImageName: "arrow.clockwise"
        )
    }
}
