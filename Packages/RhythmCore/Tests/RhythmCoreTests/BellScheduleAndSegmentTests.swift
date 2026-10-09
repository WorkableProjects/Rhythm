import XCTest
@testable import RhythmCore

final class BellSchedulePresetTests: XCTestCase {
    private let calendar = Fixtures.calendar()
    private var engine: ScheduleEngine { ScheduleEngine(calendar: calendar) }

    private func configuration(_ lunch: LunchGroup) -> ScheduleConfiguration {
        let entries = BellSchedulePreset.entries(lunch: lunch)
        var assignments: [Weekday: UUID] = [:]
        for entry in entries { for weekday in entry.weekdays { assignments[weekday] = entry.template.id } }
        return ScheduleConfiguration(templates: entries.map(\.template), weekdayAssignments: assignments)
    }

    func testAllPresetsAreValid() {
        for lunch in LunchGroup.allCases {
            for entry in BellSchedulePreset.entries(lunch: lunch) {
                XCTAssertEqual(ScheduleValidator.validate(periods: entry.template.periods), [], entry.template.name)
            }
        }
    }

    func testWeekdayAssignments() {
        let entries = BellSchedulePreset.entries(lunch: .a)
        XCTAssertEqual(entries[0].weekdays, [.monday, .wednesday, .friday])
        XCTAssertEqual(entries[1].weekdays, [.tuesday, .thursday])
        XCTAssertTrue(entries[2].weekdays.isEmpty)
        XCTAssertTrue(entries[3].weekdays.isEmpty)
    }

    func testRegularALunchTimes() {
        // Friday 9 Oct 2026 uses the regular schedule.
        let day = engine.resolveDay(Fixtures.friday, configuration: configuration(.a))
        let rows = day.periods.map { "\($0.title) \($0.startTime)-\($0.endTime)" }
        XCTAssertEqual(rows, [
            "Period 1 08:30-09:28", "Period 2 09:34-10:32", "Period 3 10:38-11:36", "Lunch 11:36-12:18",
            "Period 4 12:24-13:22", "Period 5 13:28-14:26", "Period 6 14:32-15:30"
        ])
    }

    func testAdvisoryBLunchTimes() {
        let thursday = LocalDate(year: 2026, month: 10, day: 8)
        let day = engine.resolveDay(thursday, configuration: configuration(.b))
        let rows = day.periods.map { "\($0.title) \($0.startTime)-\($0.endTime)" }
        XCTAssertEqual(rows, [
            "Period 1 08:30-09:23", "Period 2 / Advisory 09:29-10:52", "Period 3 10:58-11:51", "Period 4 11:57-12:50",
            "Lunch 12:50-13:32", "Period 5 13:38-14:31", "Period 6 14:37-15:30"
        ])
    }

    func testCollaborationDaySeminarIsOffByDefault() {
        let collab = BellSchedulePreset.collaboration()
        XCTAssertEqual(collab.periods.filter(\.isEnabled).count, 7)
        XCTAssertEqual(collab.periods.last?.title, "Senior Seminar")
        XCTAssertFalse(collab.periods.last!.isEnabled)
    }

    func testCollaborationOverrideOnADate() {
        let collab = BellSchedulePreset.collaboration()
        var config = configuration(.a)
        config.templates[collab.id] = collab
        config.overrides[Fixtures.friday] = OverrideDefinition(date: Fixtures.friday, kind: .customSchedule,
                                                                title: "Collaboration Day", templateID: collab.id)
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 12, 0), configuration: config)
        XCTAssertEqual(snapshot.activePeriod?.title, "Period 6")
        XCTAssertEqual(snapshot.day.periods.last?.title, "Lunch")
    }
}

final class LiveSegmentTests: XCTestCase {
    private let calendar = Fixtures.calendar()
    private var engine: ScheduleEngine { ScheduleEngine(calendar: calendar) }

    private var config: ScheduleConfiguration {
        let entries = BellSchedulePreset.entries(lunch: .a)
        var assignments: [Weekday: UUID] = [:]
        for entry in entries { for weekday in entry.weekdays { assignments[weekday] = entry.template.id } }
        return ScheduleConfiguration(templates: entries.map(\.template), weekdayAssignments: assignments)
    }

    private var friday: ResolvedDay { engine.resolveDay(Fixtures.friday, configuration: config) }

    func testPassingPeriodBetweenPeriodOneAndTwo() {
        let now = Fixtures.instant(Fixtures.friday, 9, 30)
        let snapshot = engine.snapshot(at: now, configuration: config)
        XCTAssertEqual(snapshot.state, .freeTime)
        XCTAssertTrue(snapshot.isPassingPeriod)
        XCTAssertEqual(snapshot.stateLabel, "Passing Period")
        XCTAssertEqual(snapshot.nextPeriod?.title, "Period 2")
        XCTAssertEqual(snapshot.remaining, 4 * 60)
    }

    func testSegmentsCoverTheDayWithoutGaps() {
        let segments = ScheduleSegments.segments(for: friday)
        XCTAssertEqual(segments.first?.kind, .beforeSchool)
        XCTAssertEqual(segments.first?.startDate, Fixtures.instant(Fixtures.friday, 7, 30))
        for (a, b) in zip(segments, segments.dropFirst()) {
            XCTAssertEqual(a.endDate, b.startDate, "\(a.period.title) → \(b.period.title)")
        }
        XCTAssertEqual(segments.last?.endDate, Fixtures.instant(Fixtures.friday, 15, 30))
        // 7 periods, 5 passing periods (Period 3 → Lunch is back to back), 1 before school.
        XCTAssertEqual(segments.filter { $0.kind == .period }.count, 7)
        XCTAssertEqual(segments.filter { $0.kind == .passing }.count, 5)
    }

    func testLiveFrameDuringPeriodIncludesFollowingPassing() throws {
        let frame = try XCTUnwrap(ScheduleSegments.liveFrame(at: Fixtures.instant(Fixtures.friday, 9, 0), day: friday))
        XCTAssertEqual(frame.current.kind, .period)
        XCTAssertEqual(frame.current.period.title, "Period 1")
        XCTAssertEqual(frame.following?.kind, .passing)
        XCTAssertEqual(frame.following?.period.title, "Period 2")
        XCTAssertEqual(frame.following?.endDate, Fixtures.instant(Fixtures.friday, 9, 34))
    }

    func testLiveFrameDuringPassingIncludesNextPeriod() throws {
        let frame = try XCTUnwrap(ScheduleSegments.liveFrame(at: Fixtures.instant(Fixtures.friday, 9, 30), day: friday))
        XCTAssertEqual(frame.current.kind, .passing)
        XCTAssertEqual(frame.current.period.title, "Period 2")
        XCTAssertEqual(frame.following?.kind, .period)
        XCTAssertEqual(frame.following?.endDate, Fixtures.instant(Fixtures.friday, 10, 32))
    }

    func testBackToBackPeriodsHaveNoPassingSegment() throws {
        let frame = try XCTUnwrap(ScheduleSegments.liveFrame(at: Fixtures.instant(Fixtures.friday, 11, 0), day: friday))
        XCTAssertEqual(frame.current.period.title, "Period 3")
        XCTAssertEqual(frame.following?.kind, .period)
        XCTAssertEqual(frame.following?.period.title, "Lunch")
    }

    func testNoFrameOutsideSchoolHours() {
        XCTAssertNil(ScheduleSegments.liveFrame(at: Fixtures.instant(Fixtures.friday, 7, 0), day: friday))
        XCTAssertNotNil(ScheduleSegments.liveFrame(at: Fixtures.instant(Fixtures.friday, 7, 45), day: friday))
        XCTAssertNil(ScheduleSegments.liveFrame(at: Fixtures.instant(Fixtures.friday, 15, 30), day: friday))
    }

    func testNextAutomaticStartSkipsWeekend() throws {
        let start = try XCTUnwrap(ScheduleSegments.nextAutomaticStart(after: Fixtures.instant(Fixtures.friday, 16, 0),
                                                                      engine: engine, configuration: config))
        XCTAssertEqual(start.date, LocalDate(year: 2026, month: 10, day: 12))
        XCTAssertEqual(start.current.kind, .beforeSchool)
        XCTAssertEqual(start.current.startDate, Fixtures.instant(LocalDate(year: 2026, month: 10, day: 12), 7, 30))
        XCTAssertEqual(start.following?.period.title, "Period 1")
    }

    func testNextAutomaticStartIsTodayBeforeSchool() throws {
        let start = try XCTUnwrap(ScheduleSegments.nextAutomaticStart(after: Fixtures.instant(Fixtures.friday, 6, 0),
                                                                      engine: engine, configuration: config))
        XCTAssertEqual(start.date, Fixtures.friday)
    }

    func testLongGapIsFreeTimeNotPassing() {
        let template = TemplateDefinition(name: "Gap", periods: [
            Fixtures.period("A", .classPeriod, 9, 0, 10, 0),
            Fixtures.period("B", .classPeriod, 11, 0, 12, 0)
        ])
        let config = ScheduleConfiguration(templates: [template], weekdayAssignments: [.friday: template.id])
        let snapshot = engine.snapshot(at: Fixtures.instant(Fixtures.friday, 10, 30), configuration: config)
        XCTAssertFalse(snapshot.isPassingPeriod)
        XCTAssertEqual(snapshot.stateLabel, "Free Time")
    }

    func testWidgetStatusPassingAndWeekendCoverage() {
        let snapshot = WidgetSnapshot.make(engine: engine, configuration: config,
                                           now: Fixtures.instant(Fixtures.friday, 8, 0), accentKey: "blue")
        let passing = snapshot.status(at: Fixtures.instant(Fixtures.friday, 9, 30), calendar: calendar)
        XCTAssertTrue(passing.isPassingPeriod)
        XCTAssertEqual(passing.next?.title, "Period 2")
        // Written Friday morning, still valid Monday.
        let monday = snapshot.status(at: Fixtures.instant(LocalDate(year: 2026, month: 10, day: 12), 9, 0), calendar: calendar)
        XCTAssertFalse(monday.isStale)
        XCTAssertEqual(monday.active?.title, "Period 1")
    }
}
