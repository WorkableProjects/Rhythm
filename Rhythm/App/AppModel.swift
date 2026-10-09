import BackgroundTasks
import Foundation
import Observation
import RhythmCore
import SwiftData
import UIKit

/// The app's composition root and feature coordinator.
///
/// It owns the persistence container, repository, and Apple-framework services, and keeps the
/// engine input (`configuration`) in sync with persisted data. Views read schedule state from
/// here and send edits through `commit(_:)`, which saves, recomputes, and refreshes
/// notifications, widgets, and the Live Activity in one place.
@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let repository: ScheduleRepository
    let preferences: RhythmPreferences
    let router = AppRouter()
    let notifications: NotificationScheduler
    let liveActivities = LiveActivityCoordinator()
    let widgetStore = WidgetSnapshotStore()

    /// Engine input built from persisted data.
    private(set) var configuration: ScheduleConfiguration = .empty
    private(set) var hasSampleData = false
    /// The user's current calendar (and so time zone). Replaced when the system changes it.
    private(set) var calendar: Calendar = .autoupdatingCurrent
    /// Incremented on time-zone, day, and clock changes so dependent views recompute.
    private(set) var clockEpoch = 0

    var recoveryMessage: String? = nil
    var saveError: String? = nil

    /// Shifts "now" for UI tests (`-RhythmClock 2026-10-09T09:30:00`, local wall time); zero in
    /// normal use. Time keeps moving from the given instant.
    private let clockOffset: TimeInterval
    @ObservationIgnored private var boundaryTask: Task<Void, Never>? = nil
    @ObservationIgnored private var liveActivityTask: Task<Void, Never>? = nil
    @ObservationIgnored private var observerTasks: [Task<Void, Never>] = []

    init(loaded: PersistenceController.Loaded, arguments: [String] = ProcessInfo.processInfo.arguments) {
        container = loaded.container
        repository = ScheduleRepository(context: loaded.container.mainContext)
        recoveryMessage = loaded.recoveryMessage

        let isUITesting = arguments.contains(PersistenceController.uiTestingArgument)
        if isUITesting, let defaults = UserDefaults(suiteName: "RhythmUITests") {
            defaults.removePersistentDomain(forName: "RhythmUITests")
            preferences = RhythmPreferences(defaults: defaults)
        } else {
            preferences = RhythmPreferences()
        }

        if arguments.contains("-RhythmNotificationsDenied") {
            notifications = NotificationScheduler(client: DeniedNotificationCenter())
        } else {
            notifications = NotificationScheduler()
        }

        if let index = arguments.firstIndex(of: "-RhythmClock"), arguments.indices.contains(index + 1),
           let fixed = AppModel.parseLocalWallTime(arguments[index + 1]) {
            clockOffset = fixed.timeIntervalSinceNow
        } else {
            clockOffset = 0
        }

        reload()
    }

    // MARK: Time

    private static func parseLocalWallTime(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: value)
    }

    var engine: ScheduleEngine { ScheduleEngine(calendar: calendar) }

    /// The current instant (or `date` translated through the test clock offset).
    func now(_ date: Date = .now) -> Date { date.addingTimeInterval(clockOffset) }

    var today: LocalDate { LocalDate(now(), calendar: calendar) }

    func snapshot(at date: Date = .now) -> ScheduleSnapshot {
        engine.snapshot(at: now(date), configuration: configuration)
    }

    func resolvedDay(_ date: LocalDate) -> ResolvedDay {
        engine.resolveDay(date, configuration: configuration)
    }

    // MARK: Lifecycle

    /// Call once at launch.
    func start() {
        observeSystemClockChanges()
        refreshIntegrations()
        Task { await notifications.refreshAuthorization() }
    }

    func sceneBecameActive() {
        handleClockChange()
        Task { await notifications.refreshAuthorization() }
    }

    func sceneEnteredBackground() {
        boundaryTask?.cancel()
        boundaryTask = nil
        widgetStore.update(configuration: configuration, engine: engine, accentKey: preferences.accent.rawValue, now: now())
        scheduleBackgroundRefresh()
    }

    /// Rebuilds the engine input from the store.
    func reload() {
        configuration = repository.configuration()
        hasSampleData = repository.hasSampleData
    }

    /// Applies `changes`, saves, and refreshes every dependent system. Returns `false` and keeps
    /// the previous data if saving fails.
    @discardableResult
    func commit(_ changes: () -> Void = {}) -> Bool {
        changes()
        do {
            try repository.save()
            saveError = nil
        } catch {
            repository.context.rollback()
            saveError = "Rhythm couldn’t save that change. \(error.localizedDescription)"
            reload()
            return false
        }
        reload()
        refreshIntegrations()
        return true
    }

    /// Recomputes notifications, the widget snapshot, and the Live Activity. Never blocks the UI
    /// and never fails loudly: each integration degrades on its own.
    func refreshIntegrations() {
        let engine = engine
        let now = now()
        widgetStore.update(configuration: configuration, engine: engine, accentKey: preferences.accent.rawValue, now: now)
        notifications.reconcile(reminders: repository.reminderDefinitions(), configuration: configuration,
                                engine: engine, featureEnabled: preferences.remindersEnabled)
        reconcileLiveActivity(engine: engine, now: now)
        scheduleBoundaryRefresh(after: now)
    }

    /// Serializes Live Activity reconciliation so overlapping refreshes can't start two activities.
    @discardableResult
    private func reconcileLiveActivity(engine: ScheduleEngine, now: Date) -> Task<Void, Never> {
        let previous = liveActivityTask
        let configuration = configuration
        let enabled = preferences.liveActivitiesEnabled
        let task = Task { [weak self] in
            await previous?.value
            await self?.liveActivities.reconcile(engine: engine, configuration: configuration, now: now, enabled: enabled)
        }
        liveActivityTask = task
        return task
    }

    /// The next bell (or the start of the next day's Live Activity window) after `date`.
    func nextLiveBoundary(after date: Date) -> Date? {
        let today = resolvedDay(LocalDate(date, calendar: calendar))
        let edges = ScheduleSegments.segments(for: today).flatMap { [$0.startDate, $0.endDate] }
        if let next = edges.filter({ $0 > date }).min() { return next }
        return ScheduleSegments.nextAutomaticStart(after: date, engine: engine, configuration: configuration)?.current.startDate
    }

    /// While Rhythm is in the foreground, refresh at every bell so the Today screen's integrations
    /// and the Live Activity switch exactly on time. In the background, Rhythm relies on scheduled
    /// Live Activities, stale-date handover, WidgetKit timelines, and background refresh instead of
    /// keeping a timer alive.
    private func scheduleBoundaryRefresh(after now: Date) {
        boundaryTask?.cancel()
        guard let next = nextLiveBoundary(after: now) else { return }
        let delay = max(1, next.timeIntervalSince(now) + 0.5)
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refreshIntegrations()
        }
    }

    /// Starts or updates the Live Activity immediately, turning the setting on if needed. Called by
    /// Settings' "Start Now" and by `StartLiveActivityIntent`, which iOS lets run in the background.
    func startLiveActivityNow() async {
        if !preferences.liveActivitiesEnabled { preferences.liveActivitiesEnabled = true }
        calendar = .autoupdatingCurrent
        reload()
        let engine = engine
        let configuration = configuration
        let now = now()
        await liveActivityTask?.value
        await liveActivities.startNow(engine: engine, configuration: configuration, now: now)
        await reconcileLiveActivity(engine: engine, now: now).value
        widgetStore.update(configuration: configuration, engine: engine, accentKey: preferences.accent.rawValue, now: now)
        scheduleBackgroundRefresh()
    }

    // MARK: Background refresh

    /// Must match `BGTaskSchedulerPermittedIdentifiers` in the Info.plist.
    nonisolated static var backgroundRefreshIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "rhythm") + ".refresh"
    }

    /// Asks iOS to wake Rhythm at the next bell. iOS decides the actual time (it may be later or
    /// skipped), so this improves Live Activity updates but isn't relied on for correctness.
    func scheduleBackgroundRefresh() {
        guard let next = nextLiveBoundary(after: now()) else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundRefreshIdentifier)
        request.earliestBeginDate = next
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Runs when iOS grants a background refresh: updates every integration, then schedules the next.
    func handleBackgroundRefresh() async {
        calendar = .autoupdatingCurrent
        reload()
        let engine = engine
        let now = now()
        widgetStore.update(configuration: configuration, engine: engine, accentKey: preferences.accent.rawValue, now: now)
        notifications.reconcile(reminders: repository.reminderDefinitions(), configuration: configuration,
                                engine: engine, featureEnabled: preferences.remindersEnabled)
        await reconcileLiveActivity(engine: engine, now: now).value
        scheduleBackgroundRefresh()
    }

    private func handleClockChange() {
        calendar = .autoupdatingCurrent
        clockEpoch += 1
        refreshIntegrations()
    }

    private func observeSystemClockChanges() {
        guard observerTasks.isEmpty else { return }
        let names: [Notification.Name] = [
            .NSSystemTimeZoneDidChange,
            .NSCalendarDayChanged,
            .NSSystemClockDidChange,
            UIApplication.significantTimeChangeNotification
        ]
        observerTasks = names.map { name in
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    self?.handleClockChange()
                }
            }
        }
    }

    // MARK: Data management

    func insertSample() {
        commit { repository.insertSampleTimetable() }
    }

    /// Loads the school's bell schedule (see `BellSchedulePreset`) and finishes onboarding.
    func applyBellSchedule(lunch: LunchGroup) {
        preferences.lunchGroup = lunch
        if commit({ repository.insertBellSchedule(lunch: lunch) }) {
            preferences.hasCompletedOnboarding = true
        }
    }

    /// Copies one bell schedule template; returns the copy (or the existing one with that name).
    @discardableResult
    func copyBellSchedule(_ kind: BellSchedulePreset.Kind, lunch: LunchGroup, assignWeekdays: Bool) -> ScheduleTemplate? {
        if kind.dependsOnLunch { preferences.lunchGroup = lunch }
        var copied: ScheduleTemplate?
        guard commit({ copied = repository.copyBellSchedule(kind, lunch: lunch, assignWeekdays: assignWeekdays) }) else { return nil }
        preferences.hasCompletedOnboarding = true
        return copied
    }

    func removeSample() {
        commit { repository.removeSampleTimetable() }
    }

    /// Deletes every schedule, override, reminder, and Quicklink, and resets preferences.
    func deleteAllData() {
        commit { repository.deleteAllData() }
        preferences.reset()
        widgetStore.removeSnapshot()
        router.todayDate = nil
        router.scheduleDate = nil
        router.presentedPeriod = nil
        Task { await liveActivities.endAll() }
    }

    func importReplacingAll(_ export: RhythmExport) -> Bool {
        do {
            try repository.replaceAll(with: export)
            saveError = nil
        } catch {
            saveError = "Import failed and your previous data was kept. \(error.localizedDescription)"
            reload()
            return false
        }
        reload()
        refreshIntegrations()
        return true
    }

    /// Re-applies preferences that affect integrations (e.g. after toggling Live Activities).
    func preferencesDidChange() {
        refreshIntegrations()
    }
}

/// Used by UI tests to simulate a user who denied notifications.
private struct DeniedNotificationCenter: NotificationCenterClient {
    func authorization() async -> NotificationAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func pendingIdentifiers() async -> [String] { [] }
    func add(_ notification: PlannedNotification) async throws {}
    func removePending(identifiers: [String]) async {}
}
