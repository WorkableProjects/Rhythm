import XCTest
@testable import RhythmCore

final class WidgetSnapshotTests: XCTestCase {
    private let calendar = Fixtures.calendar()

    private func makeSnapshot(at now: Date, overrides: [OverrideDefinition] = []) -> WidgetSnapshot {
        let (config, _) = Fixtures.weekConfiguration(overrides: overrides)
        return WidgetSnapshot.make(engine: ScheduleEngine(calendar: calendar), configuration: config, now: now, accentKey: "blue")
    }

    func testRoundTripAndStatus() throws {
        let snapshot = makeSnapshot(at: Fixtures.instant(Fixtures.friday, 7, 0))
        let decoded = try WidgetSnapshotCodec.decode(WidgetSnapshotCodec.encode(snapshot)).get()
        XCTAssertEqual(decoded, snapshot)

        let status = decoded.status(at: Fixtures.instant(Fixtures.friday, 9, 30), calendar: calendar)
        XCTAssertEqual(status.state, .inProgress)
        XCTAssertEqual(status.active?.title, "Biology")
        XCTAssertEqual(status.next?.title, "Algebra II")
        XCTAssertTrue(status.nextIsToday)

        XCTAssertEqual(decoded.status(at: Fixtures.instant(Fixtures.friday, 9, 57), calendar: calendar).state, .freeTime)
        XCTAssertEqual(decoded.status(at: Fixtures.instant(Fixtures.friday, 7, 30), calendar: calendar).state, .upcoming)
        let evening = decoded.status(at: Fixtures.instant(Fixtures.friday, 18, 0), calendar: calendar)
        XCTAssertEqual(evening.state, .dayComplete)
        XCTAssertFalse(evening.nextIsToday)
        XCTAssertEqual(decoded.status(at: Fixtures.instant(Fixtures.saturday, 10, 0), calendar: calendar).state, .noSchool)
    }

    func testPayloadIsSmall() throws {
        let data = try WidgetSnapshotCodec.encode(makeSnapshot(at: Fixtures.instant(Fixtures.friday, 7, 0)))
        XCTAssertLessThan(data.count, 8 * 1024)
    }

    func testMissingCorruptNewerAndStale() throws {
        XCTAssertEqual(WidgetSnapshotCodec.decode(nil).failure, .missing)
        XCTAssertEqual(WidgetSnapshotCodec.decode(Data("{oops".utf8)).failure, .corrupt)

        var newer = makeSnapshot(at: Fixtures.instant(Fixtures.friday, 7, 0))
        newer.version = 2
        XCTAssertEqual(WidgetSnapshotCodec.decode(try WidgetSnapshotCodec.encode(newer)).failure, .unsupportedVersion(2))

        let snapshot = makeSnapshot(at: Fixtures.instant(Fixtures.friday, 7, 0))
        let later = Fixtures.instant(LocalDate(year: 2026, month: 10, day: 20), 9, 0)
        XCTAssertTrue(snapshot.status(at: later, calendar: calendar).isStale)
    }

    func testTransitionDates() {
        let snapshot = makeSnapshot(at: Fixtures.instant(Fixtures.friday, 10, 30))
        let dates = snapshot.transitionDates(after: Fixtures.instant(Fixtures.friday, 10, 30), limit: 3)
        XCTAssertEqual(dates, [
            Fixtures.instant(Fixtures.friday, 10, 55),
            Fixtures.instant(Fixtures.friday, 11, 30),
            Fixtures.instant(Fixtures.friday, 11, 35)
        ])
    }

    func testUnconfiguredSnapshot() {
        let snapshot = WidgetSnapshot.make(engine: ScheduleEngine(calendar: calendar), configuration: .empty,
                                           now: Fixtures.instant(Fixtures.friday, 9, 0), accentKey: "blue")
        XCTAssertEqual(snapshot.status(at: Fixtures.instant(Fixtures.friday, 9, 0), calendar: calendar).state, .scheduleNeeded)
    }
}

final class ValueTypeTests: XCTestCase {
    func testLocalDateKeys() {
        XCTAssertEqual(LocalDate(key: "2026-10-09"), Fixtures.friday)
        XCTAssertNil(LocalDate(key: "2026-02-30"))
        XCTAssertNil(LocalDate(key: "2026-1-9"))
        XCTAssertNil(LocalDate(key: "garbage"))
        XCTAssertEqual(Fixtures.friday.key, "2026-10-09")
        XCTAssertEqual(Fixtures.friday.weekday(in: Fixtures.calendar()), .friday)
        XCTAssertEqual(Fixtures.friday.adding(days: -9, calendar: Fixtures.calendar()), LocalDate(year: 2026, month: 9, day: 30))
    }

    func testWeekdayOrdering() {
        var calendar = Fixtures.calendar()
        calendar.firstWeekday = 2
        XCTAssertEqual(Weekday.ordered(for: calendar).first, .monday)
        XCTAssertEqual(Weekday.ordered(for: calendar).last, .sunday)
    }

    func testDeepLinkRoundTrip() {
        let id = UUID()
        let links: [DeepLink] = [.today(date: nil), .today(date: Fixtures.friday), .period(id: id, date: Fixtures.friday),
                                 .schedule(date: nil), .quicklinks, .settings]
        for link in links {
            XCTAssertEqual(DeepLink(url: link.url), link)
        }
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com")!))
        XCTAssertNil(DeepLink(url: URL(string: "rhythm://period/not-a-uuid")!))
    }

    func testUnknownKindsDecodeSafely() throws {
        let kind = try JSONDecoder().decode([PeriodKind].self, from: Data(#"["class","assembly"]"#.utf8))
        XCTAssertEqual(kind, [.classPeriod, .other])
    }

    func testClockTimeDescription() {
        XCTAssertEqual(ClockTime(hour: 8, minute: 5).description, "08:05")
    }
}
