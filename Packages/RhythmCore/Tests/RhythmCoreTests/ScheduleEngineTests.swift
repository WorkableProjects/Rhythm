import XCTest
@testable import RhythmCore

final class ScheduleEngineTests: XCTestCase {
    private let calendar = Fixtures.calendar()
    private var engine: ScheduleEngine { ScheduleEngine(calendar: calendar) }

    func testActiveClassMidPeriod() {
        let (config, _) = Fixtures.weekConfiguration()
        let now = Fixtures.instant(Fixtures.friday, 9, 30)
        let snapshot = engine.snapshot(at: now, configuration: config)

        XCTAssertEqual(snapshot.state, .inProgress)
        XCTAssertEqual(snapshot.activePeriod?.title, "Biology")
        XCTAssertEqual(snapshot.nextPeriod?.title, "Algebra II")
        XCTAssertEqual(snapshot.previousPeriod?.title, "English")
    }

    func testActiveLunchPeriod() {
        let (config, _) = Fixtures.weekConfiguration()
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 11, 10), configuration: config)
        XCTAssertEqual(snapshot.state, .inProgress)
        XCTAssertEqual(snapshot.activePeriod?.kind, .lunch)
        XCTAssertEqual(snapshot.activePeriod?.title, "Lunch")
    }

    func testExactStartBoundaryIsActive() {
        let (config, _) = Fixtures.weekConfiguration()
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 9, 0), configuration: config)
        XCTAssertEqual(snapshot.activePeriod?.title, "Biology")
    }

    func testExactEndBoundaryIsNoLongerActive() {
        let (config, _) = Fixtures.weekConfiguration()
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 9, 55), configuration: config)
        XCTAssertEqual(snapshot.state, .freeTime)
        XCTAssertNil(snapshot.activePeriod)
        XCTAssertEqual(snapshot.previousPeriod?.title, "Biology")
        XCTAssertEqual(snapshot.nextPeriod?.title, "Algebra II")
    }

    func testAdjacentPeriodsHandOverAtBoundary() {
        // Algebra II ends at 10:55 exactly when Lunch starts.
        let (config, _) = Fixtures.weekConfiguration()
        let before = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 10, 54, second: 59), configuration: config)
        let at = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 10, 55), configuration: config)
        XCTAssertEqual(before.activePeriod?.title, "Algebra II")
        XCTAssertEqual(at.activePeriod?.title, "Lunch")
        XCTAssertEqual(at.state, .inProgress)
    }

    func testGapBetweenPeriodsIsFreeTime() {
        let (config, _) = Fixtures.weekConfiguration()
        let now = Fixtures.instant(Fixtures.friday, 11, 32)
        let snapshot = engine.snapshot(at: now, configuration: config)
        XCTAssertEqual(snapshot.state, .freeTime)
        XCTAssertEqual(snapshot.nextPeriod?.title, "World History")
        XCTAssertEqual(snapshot.remaining, 180)
        XCTAssertEqual(snapshot.progress!, 0.4, accuracy: 0.0001)
    }

    func testBeforeFirstPeriodIsUpcoming() {
        let (config, _) = Fixtures.weekConfiguration()
        let now = Fixtures.instant(Fixtures.friday, 7, 30)
        let snapshot = engine.snapshot(at: now, configuration: config)
        XCTAssertEqual(snapshot.state, .upcoming)
        XCTAssertNil(snapshot.previousPeriod)
        XCTAssertEqual(snapshot.nextPeriod?.title, "English")
        XCTAssertEqual(snapshot.remaining, 30 * 60)
        XCTAssertNil(snapshot.progress)
    }

    func testAfterFinalPeriodIsDayComplete() {
        let (config, _) = Fixtures.weekConfiguration()
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 15, 0), configuration: config)
        XCTAssertEqual(snapshot.state, .dayComplete)
        XCTAssertNil(snapshot.activePeriod)
        XCTAssertNil(snapshot.nextPeriod)
        XCTAssertNil(snapshot.remaining)
        XCTAssertEqual(snapshot.previousPeriod?.title, "Physical Education")
    }

    func testNoSchoolOverride() {
        let override = OverrideDefinition(date: Fixtures.friday, kind: .noSchool, title: "Teacher Workday")
        let (config, _) = Fixtures.weekConfiguration(overrides: [override])
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 9, 30), configuration: config)
        XCTAssertEqual(snapshot.state, .noSchool)
        XCTAssertNil(snapshot.activePeriod)
        XCTAssertEqual(snapshot.day.source, .noSchoolOverride(id: override.id, title: "Teacher Workday"))
    }

    func testCustomOverrideTakesPriorityOverWeekdayTemplate() {
        let assembly = Fixtures.period("Assembly", .other, 9, 0, 10, 0)
        let override = OverrideDefinition(date: Fixtures.friday, kind: .customSchedule, title: "Assembly Day", periods: [assembly])
        let (config, _) = Fixtures.weekConfiguration(overrides: [override])
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 9, 30), configuration: config)
        XCTAssertEqual(snapshot.activePeriod?.title, "Assembly")
        XCTAssertEqual(snapshot.day.periods.count, 1)
        XCTAssertEqual(snapshot.day.source.overrideID, override.id)
    }

    func testCustomOverrideCanUseAnotherTemplate() {
        let lateStart = TemplateDefinition(name: "Late Start", periods: [Fixtures.period("Period 1", .classPeriod, 10, 0, 10, 45)])
        let (base, template) = Fixtures.weekConfiguration()
        let override = OverrideDefinition(date: Fixtures.friday, kind: .customSchedule, title: "Late Start", templateID: lateStart.id)
        let config = ScheduleConfiguration(templates: [template, lateStart], weekdayAssignments: base.weekdayAssignments, overrides: [override])
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 9, 0), configuration: config)
        XCTAssertEqual(snapshot.state, .upcoming)
        XCTAssertEqual(snapshot.nextPeriod?.title, "Period 1")
        XCTAssertEqual(snapshot.day.source.templateID, lateStart.id)
    }

    func testMissingWeekdayAssignment() {
        let (config, _) = Fixtures.weekConfiguration()
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.saturday, 10, 0), configuration: config)
        XCTAssertEqual(snapshot.state, .noSchool)
        XCTAssertEqual(snapshot.day.source, .unassigned(.saturday))
    }

    func testNoTemplatesMeansScheduleNeeded() {
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 10, 0), configuration: .empty)
        XCTAssertEqual(snapshot.state, .scheduleNeeded)
    }

    func testAssignmentToDeletedTemplateIsTreatedAsUnassigned() {
        let template = TemplateDefinition(name: "A", periods: [Fixtures.period("Math", .classPeriod, 9, 0, 10, 0)])
        let config = ScheduleConfiguration(templates: [template], weekdayAssignments: [.friday: UUID()])
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 9, 30), configuration: config)
        XCTAssertEqual(snapshot.state, .noSchool)
    }

    func testInvalidAndOverlappingPeriodsAreSkippedNotDoubleActive() {
        let periods = [
            Fixtures.period("Math", .classPeriod, 9, 0, 10, 0),
            Fixtures.period("Science", .classPeriod, 9, 30, 10, 30), // overlaps Math
            Fixtures.period("Broken", .classPeriod, 11, 0, 10, 0),   // ends before start
            Fixtures.period("Zero", .classPeriod, 12, 0, 12, 0),     // zero length
            Fixtures.period("Art", .classPeriod, 13, 0, 14, 0, enabled: false)
        ]
        let template = TemplateDefinition(name: "Messy", periods: periods)
        let config = ScheduleConfiguration(templates: [template], weekdayAssignments: [.friday: template.id])

        let day = engine.resolveDay(Fixtures.friday, configuration: config)
        XCTAssertEqual(day.periods.map(\.title), ["Math"])
        XCTAssertTrue(day.issues.contains { if case .overlap = $0 { true } else { false } })
        XCTAssertTrue(day.issues.contains { if case .endNotAfterStart = $0 { true } else { false } })

        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 9, 45), configuration: config)
        XCTAssertEqual(snapshot.activePeriod?.title, "Math")
        XCTAssertEqual(snapshot.state, .inProgress)
    }

    func testSixClassesPlusLunchTemplate() {
        let (config, _) = Fixtures.weekConfiguration()
        let day = engine.resolveDay(Fixtures.friday, configuration: config)
        XCTAssertEqual(day.periods.count, 7)
        XCTAssertEqual(day.periods.filter { $0.kind == .classPeriod }.count, 6)
        XCTAssertEqual(day.periods.filter { $0.kind == .lunch }.count, 1)
        XCTAssertTrue(day.issues.isEmpty)
        XCTAssertEqual(day.periods.map(\.startDate), day.periods.map(\.startDate).sorted())
    }

    func testPeriodsAreSortedChronologicallyRegardlessOfInputOrder() {
        let template = TemplateDefinition(name: "Shuffled", periods: [
            Fixtures.period("Third", .classPeriod, 11, 0, 12, 0),
            Fixtures.period("First", .classPeriod, 8, 0, 9, 0),
            Fixtures.period("Second", .classPeriod, 9, 0, 10, 0)
        ])
        let config = ScheduleConfiguration(templates: [template], weekdayAssignments: [.friday: template.id])
        XCTAssertEqual(engine.resolveDay(Fixtures.friday, configuration: config).periods.map(\.title), ["First", "Second", "Third"])
    }

    func testRemainingAndProgressFromInjectedNow() {
        let (config, _) = Fixtures.weekConfiguration()
        // English 8:00–8:55; at 8:11 there are 44 minutes left and progress is 11/55.
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 8, 11), configuration: config)
        XCTAssertEqual(snapshot.remaining, 44 * 60)
        XCTAssertEqual(snapshot.progress!, 11.0 / 55.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.countdownTarget, Fixtures.instant(Fixtures.friday, 8, 55))
        XCTAssertEqual(snapshot.nextTransition, Fixtures.instant(Fixtures.friday, 8, 55))
    }

    func testRecomputingLaterNeverDrifts() {
        // Simulates backgrounding: a later recomputation depends only on the new instant.
        let (config, _) = Fixtures.weekConfiguration()
        let early = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 8, 0), configuration: config)
        let later = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 8, 50, second: 30), configuration: config)
        XCTAssertEqual(early.remaining, 55 * 60)
        XCTAssertEqual(later.remaining, 270)
    }

    func testResolvedPeriodClampsProgressAndRemaining() {
        let (config, _) = Fixtures.weekConfiguration()
        let period = engine.resolveDay(Fixtures.friday, configuration: config).periods[0]
        XCTAssertEqual(period.progress(at: Fixtures.instant(Fixtures.friday, 7, 0)), 0)
        XCTAssertEqual(period.progress(at: Fixtures.instant(Fixtures.friday, 12, 0)), 1)
        XCTAssertEqual(period.remaining(at: Fixtures.instant(Fixtures.friday, 12, 0)), 0)
    }

    // MARK: Time zones and daylight saving

    func testSpringForwardDayUsesRealInstants() {
        // US DST began 8 March 2026 at 2:00 AM in Los Angeles; the day is 23 hours long.
        let date = LocalDate(year: 2026, month: 3, day: 8)
        let template = TemplateDefinition(name: "Sunday", periods: [
            Fixtures.period("Early", .other, 1, 0, 3, 30),
            Fixtures.period("Morning", .classPeriod, 8, 0, 9, 0)
        ])
        let config = ScheduleConfiguration(templates: [template], weekdayAssignments: [.sunday: template.id])
        let day = engine.resolveDay(date, configuration: config)

        XCTAssertEqual(day.periods.count, 2)
        // 1:00 PST → 3:30 PDT is only 1.5 real hours.
        XCTAssertEqual(day.periods[0].duration, 90 * 60)
        XCTAssertEqual(day.periods[1].duration, 3600)
        let startOfDay = date.startDate(in: calendar)!
        let nextDay = date.adding(days: 1, calendar: calendar).startDate(in: calendar)!
        XCTAssertEqual(nextDay.timeIntervalSince(startOfDay), 23 * 3600)
        // 8:00 local is 7 real hours after midnight on this day.
        XCTAssertEqual(day.periods[1].startDate.timeIntervalSince(startOfDay), 7 * 3600)
    }

    func testNonexistentWallTimeResolvesForward() {
        let date = LocalDate(year: 2026, month: 3, day: 8)
        let resolved = date.date(at: ClockTime(hour: 2, minute: 30), in: calendar)!
        // 2:30 AM does not exist; the next valid instant is 3:00 AM PDT.
        XCTAssertEqual(calendar.component(.hour, from: resolved), 3)
    }

    func testFallBackDayUsesRealInstants() {
        // US DST ended 1 November 2026; the day is 25 hours long.
        let date = LocalDate(year: 2026, month: 11, day: 1)
        let template = TemplateDefinition(name: "Sunday", periods: [Fixtures.period("Morning", .classPeriod, 8, 0, 9, 0)])
        let config = ScheduleConfiguration(templates: [template], weekdayAssignments: [.sunday: template.id])
        let day = engine.resolveDay(date, configuration: config)
        let startOfDay = date.startDate(in: calendar)!
        XCTAssertEqual(day.periods[0].startDate.timeIntervalSince(startOfDay), 9 * 3600)
        XCTAssertEqual(date.adding(days: 1, calendar: calendar), LocalDate(year: 2026, month: 11, day: 2))
    }

    func testSameWallTimesInDifferentTimeZones() {
        let (config, _) = Fixtures.weekConfiguration()
        let tokyo = Fixtures.calendar("Asia/Tokyo")
        let tokyoEngine = ScheduleEngine(calendar: tokyo)
        let now = Fixtures.instant(Fixtures.friday, 9, 30, calendar: tokyo)
        let snapshot = tokyoEngine.snapshot(at: now, configuration: config)
        XCTAssertEqual(snapshot.activePeriod?.title, "Biology")
        XCTAssertEqual(tokyo.component(.hour, from: snapshot.activePeriod!.startDate), 9)
    }

    func testNextPeriodSearchesFollowingDays() {
        let (config, _) = Fixtures.weekConfiguration()
        let fridayEvening = Fixtures.instant(Fixtures.friday, 18, 0)
        let result = engine.nextPeriod(after: fridayEvening, configuration: config)
        XCTAssertEqual(result?.day.date, LocalDate(year: 2026, month: 10, day: 12)) // Monday
        XCTAssertEqual(result?.period.title, "English")
    }

    func testMidnightEndOfDayPeriod() {
        let template = TemplateDefinition(name: "Late", periods: [Fixtures.period("Study", .other, 23, 0, 24, 0)])
        let config = ScheduleConfiguration(templates: [template], weekdayAssignments: [.friday: template.id])
        let day = engine.resolveDay(Fixtures.friday, configuration: config)
        XCTAssertEqual(day.periods.first?.endDate, Fixtures.instant(Fixtures.saturday, 0, 0))
    }
}
