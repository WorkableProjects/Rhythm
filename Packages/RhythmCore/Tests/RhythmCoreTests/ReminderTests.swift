import XCTest
@testable import RhythmCore

/// In-memory stand-in for `UNUserNotificationCenter`.
actor FakeNotificationCenter: NotificationCenterClient {
    var status: NotificationAuthorization
    private(set) var pending: [String: PlannedNotification] = [:]
    private(set) var addCount = 0

    init(status: NotificationAuthorization = .authorized) { self.status = status }

    func setStatus(_ status: NotificationAuthorization) { self.status = status }
    func authorization() async -> NotificationAuthorization { status }
    func requestAuthorization() async throws -> Bool { status.allowsScheduling }
    func pendingIdentifiers() async -> [String] { Array(pending.keys) }
    func add(_ notification: PlannedNotification) async throws {
        addCount += 1
        pending[notification.id] = notification
    }
    func removePending(identifiers: [String]) async {
        for id in identifiers { pending[id] = nil }
    }
    func pendingNotifications() -> [PlannedNotification] { Array(pending.values) }
}

final class ReminderPlannerTests: XCTestCase {
    private let calendar = Fixtures.calendar()
    private var planner: ReminderPlanner { ReminderPlanner(engine: ScheduleEngine(calendar: calendar), horizonDays: 7) }

    func testRecurringReminderPlansEachSchoolDayOnly() {
        let (config, template) = Fixtures.weekConfiguration()
        let pe = template.periods.last!
        let reminder = ReminderDefinition(periodID: pe.id, title: "Bring gym clothes", trigger: .beforeStart(minutes: 15))
        // Friday 7:00 → horizon Fri…Thu: Fri, Mon, Tue, Wed, Thu = 5 school days.
        let plan = planner.plan(reminders: [reminder], configuration: config, now: Fixtures.instant(Fixtures.friday, 7, 0))
        XCTAssertEqual(plan.count, 5)
        XCTAssertEqual(plan.first?.fireDate, Fixtures.instant(Fixtures.friday, 13, 20))
        XCTAssertEqual(plan.first?.title, "Bring gym clothes")
        XCTAssertEqual(plan.first?.body, "Physical Education")
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
    }

    func testPastOccurrencesAreNotPlanned() {
        let (config, template) = Fixtures.weekConfiguration()
        let reminder = ReminderDefinition(periodID: template.periods[0].id, title: "", trigger: .beforeStart(minutes: 5))
        let plan = planner.plan(reminders: [reminder], configuration: config, now: Fixtures.instant(Fixtures.friday, 12, 0))
        XCTAssertFalse(plan.contains { $0.date == Fixtures.friday })
        XCTAssertEqual(plan.first?.title, "English") // empty title falls back to the period title
    }

    func testNoSchoolOverrideSuppressesEvents() {
        let (config, template) = Fixtures.weekConfiguration(overrides: [OverrideDefinition(date: Fixtures.friday, kind: .noSchool)])
        let reminder = ReminderDefinition(periodID: template.periods[1].id, title: "Lab", trigger: .beforeStart(minutes: 10))
        let plan = planner.plan(reminders: [reminder], configuration: config, now: Fixtures.instant(Fixtures.friday, 6, 0))
        XCTAssertFalse(plan.contains { $0.date == Fixtures.friday })
        XCTAssertEqual(plan.count, 4)
    }

    func testDeletedOrDisabledPeriodPlansNothing() {
        var (config, template) = Fixtures.weekConfiguration()
        let reminder = ReminderDefinition(periodID: template.periods[1].id, title: "Lab", trigger: .beforeStart(minutes: 10))
        template.periods[1].isEnabled = false
        config.templates[template.id] = template
        XCTAssertTrue(planner.plan(reminders: [reminder], configuration: config, now: Fixtures.instant(Fixtures.friday, 6, 0)).isEmpty)

        template.periods.remove(at: 1)
        config.templates[template.id] = template
        XCTAssertTrue(planner.plan(reminders: [reminder], configuration: config, now: Fixtures.instant(Fixtures.friday, 6, 0)).isEmpty)
    }

    func testOneOffReminder() {
        let (config, template) = Fixtures.weekConfiguration()
        let reminder = ReminderDefinition(periodID: template.periods[2].id, title: "Turn in worksheet",
                                          trigger: .oneOff(date: Fixtures.friday, time: ClockTime(hour: 9, minute: 58)))
        let plan = planner.plan(reminders: [reminder], configuration: config, now: Fixtures.instant(Fixtures.friday, 6, 0))
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].fireDate, Fixtures.instant(Fixtures.friday, 9, 58))
        XCTAssertEqual(DeepLink(url: plan[0].deepLink), .period(id: template.periods[2].id, date: Fixtures.friday))
    }

    func testPlanIsBounded() {
        let (config, template) = Fixtures.weekConfiguration()
        let reminders = template.periods.map { ReminderDefinition(periodID: $0.id, title: $0.title, trigger: .beforeStart(minutes: 2)) }
        let longPlanner = ReminderPlanner(engine: ScheduleEngine(calendar: calendar), horizonDays: 30, maximumRequests: 44)
        let plan = longPlanner.plan(reminders: reminders, configuration: config, now: Fixtures.instant(Fixtures.friday, 6, 0))
        XCTAssertEqual(plan.count, 44)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
    }

    func testDisabledRuleIsIgnored() {
        let (config, template) = Fixtures.weekConfiguration()
        let reminder = ReminderDefinition(periodID: template.periods[0].id, title: "x", trigger: .beforeStart(minutes: 5), isEnabled: false)
        XCTAssertTrue(planner.plan(reminders: [reminder], configuration: config, now: Fixtures.instant(Fixtures.friday, 6, 0)).isEmpty)
    }
}

final class ReminderReconcilerTests: XCTestCase {
    private let calendar = Fixtures.calendar()

    private func plan(_ reminders: [ReminderDefinition], _ config: ScheduleConfiguration) -> [PlannedNotification] {
        ReminderPlanner(engine: ScheduleEngine(calendar: calendar), horizonDays: 7)
            .plan(reminders: reminders, configuration: config, now: Fixtures.instant(Fixtures.friday, 6, 0))
    }

    func testDuplicateSchedulingIsIdempotent() async {
        let (config, template) = Fixtures.weekConfiguration()
        let reminders = [ReminderDefinition(periodID: template.periods[0].id, title: "Read", trigger: .beforeStart(minutes: 5))]
        let center = FakeNotificationCenter()
        let reconciler = ReminderReconciler(client: center)

        let first = await reconciler.reconcile(plan: plan(reminders, config), featureEnabled: true)
        let second = await reconciler.reconcile(plan: plan(reminders, config), featureEnabled: true)

        XCTAssertEqual(first.added.count, 5)
        XCTAssertTrue(second.added.isEmpty)
        XCTAssertTrue(second.removed.isEmpty)
        let pendingCount = await center.pendingIdentifiers().count
        let addCount = await center.addCount
        XCTAssertEqual(pendingCount, 5)
        XCTAssertEqual(addCount, 5)
    }

    func testChangedReminderReplacesOldRequests() async {
        let (config, template) = Fixtures.weekConfiguration()
        var reminder = ReminderDefinition(periodID: template.periods[0].id, title: "Read", trigger: .beforeStart(minutes: 5))
        let center = FakeNotificationCenter()
        let reconciler = ReminderReconciler(client: center)
        _ = await reconciler.reconcile(plan: plan([reminder], config), featureEnabled: true)

        reminder.trigger = .beforeStart(minutes: 10)
        let result = await reconciler.reconcile(plan: plan([reminder], config), featureEnabled: true)
        XCTAssertEqual(result.removed.count, 5)
        XCTAssertEqual(result.added.count, 5)
        let pending = await center.pendingNotifications()
        XCTAssertEqual(pending.count, 5)
        XCTAssertTrue(pending.allSatisfy { calendar.component(.minute, from: $0.fireDate) == 50 })
    }

    func testDeletedPeriodCancelsRelatedRequests() async {
        var (config, template) = Fixtures.weekConfiguration()
        let reminder = ReminderDefinition(periodID: template.periods[3].id, title: "Lunch money", trigger: .beforeStart(minutes: 0))
        let center = FakeNotificationCenter()
        let reconciler = ReminderReconciler(client: center)
        _ = await reconciler.reconcile(plan: plan([reminder], config), featureEnabled: true)

        template.periods.remove(at: 3)
        config.templates[template.id] = template
        let result = await reconciler.reconcile(plan: plan([reminder], config), featureEnabled: true)
        XCTAssertEqual(result.removed.count, 5)
        let pendingCount = await center.pendingIdentifiers().count
        XCTAssertEqual(pendingCount, 0)
    }

    func testDeniedPermissionDoesNotClaimScheduling() async {
        let (config, template) = Fixtures.weekConfiguration()
        let reminder = ReminderDefinition(periodID: template.periods[0].id, title: "Read", trigger: .beforeStart(minutes: 5))
        let center = FakeNotificationCenter(status: .denied)
        let result = await ReminderReconciler(client: center).reconcile(plan: plan([reminder], config), featureEnabled: true)
        XCTAssertEqual(result.status, .notAuthorized)
        XCTAssertEqual(result.scheduledCount, 0)
        XCTAssertTrue(result.added.isEmpty)
        // The rule itself is untouched (it lives in Rhythm's data, not the notification center).
        XCTAssertTrue(reminder.isEnabled)
    }

    func testRevokedPermissionClearsPendingRequests() async {
        let (config, template) = Fixtures.weekConfiguration()
        let reminder = ReminderDefinition(periodID: template.periods[0].id, title: "Read", trigger: .beforeStart(minutes: 5))
        let center = FakeNotificationCenter()
        let reconciler = ReminderReconciler(client: center)
        _ = await reconciler.reconcile(plan: plan([reminder], config), featureEnabled: true)
        await center.setStatus(.denied)
        let result = await reconciler.reconcile(plan: plan([reminder], config), featureEnabled: true)
        XCTAssertEqual(result.status, .notAuthorized)
        let pendingCount = await center.pendingIdentifiers().count
        XCTAssertEqual(pendingCount, 0)
    }

    func testFeatureDisabledRemovesOnlyRhythmRequests() async {
        let center = FakeNotificationCenter()
        let foreign = PlannedNotification(id: "other.thing", ruleID: UUID(), periodID: UUID(), date: Fixtures.friday,
                                          title: "", body: "", fireDate: Date(), deepLink: DeepLink.today(date: nil).url)
        try? await center.add(foreign)
        let (config, template) = Fixtures.weekConfiguration()
        let reminder = ReminderDefinition(periodID: template.periods[0].id, title: "Read", trigger: .beforeStart(minutes: 5))
        let reconciler = ReminderReconciler(client: center)
        _ = await reconciler.reconcile(plan: plan([reminder], config), featureEnabled: true)
        let result = await reconciler.reconcile(plan: plan([reminder], config), featureEnabled: false)
        XCTAssertEqual(result.status, .featureDisabled)
        let pending = await center.pendingIdentifiers()
        XCTAssertEqual(pending, ["other.thing"])
    }
}
