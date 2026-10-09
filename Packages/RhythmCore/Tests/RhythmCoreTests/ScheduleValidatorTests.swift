import XCTest
@testable import RhythmCore

final class ScheduleValidatorTests: XCTestCase {
    func testStartEqualsEnd() {
        let issues = ScheduleValidator.validate(periods: [Fixtures.period("Math", .classPeriod, 9, 0, 9, 0)])
        XCTAssertEqual(issues.count, 1)
        guard case .endNotAfterStart = issues[0] else { return XCTFail("Expected endNotAfterStart") }
        XCTAssertEqual(issues[0].message, "Math must end after it starts.")
    }

    func testEndBeforeStart() {
        let issues = ScheduleValidator.validate(periods: [Fixtures.period("Math", .classPeriod, 10, 0, 9, 0)])
        guard case .endNotAfterStart = issues.first else { return XCTFail("Expected endNotAfterStart") }
    }

    func testOverlappingPeriodsProduceSpecificCopy() {
        let biology = Fixtures.period("Biology", .classPeriod, 10, 0, 11, 5)
        let lunch = Fixtures.period("Lunch", .lunch, 11, 0, 11, 30)
        let issues = ScheduleValidator.validate(periods: [lunch, biology])
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.message, "Lunch overlaps Biology by 5 minutes.")
        XCTAssertEqual(Set(issues.first?.periodIDs ?? []), [biology.id, lunch.id])
    }

    func testFullyContainedOverlapMinutes() {
        let long = Fixtures.period("Block", .classPeriod, 9, 0, 12, 0)
        let short = Fixtures.period("Assembly", .other, 10, 0, 10, 30)
        XCTAssertEqual(ScheduleValidator.validate(periods: [long, short]).first?.message, "Assembly overlaps Block by 30 minutes.")
    }

    func testDisabledPeriodsDoNotCountAsOverlapping() {
        let issues = ScheduleValidator.validate(periods: [
            Fixtures.period("Math", .classPeriod, 9, 0, 10, 0),
            Fixtures.period("Old Math", .classPeriod, 9, 0, 10, 0, enabled: false)
        ])
        XCTAssertTrue(issues.isEmpty)
    }

    func testDuplicateWeekdayAssignments() {
        let a = UUID(), b = UUID()
        let issues = ScheduleValidator.validate(
            assignments: [(.monday, a), (.monday, b), (.tuesday, a)],
            knownTemplateIDs: [a, b]
        )
        XCTAssertEqual(issues, [.duplicateWeekdayAssignment(.monday)])
    }

    func testUnknownTemplateAssignment() {
        let issues = ScheduleValidator.validate(assignments: [(.monday, UUID())], knownTemplateIDs: [])
        guard case .unknownTemplate = issues.first else { return XCTFail("Expected unknownTemplate") }
    }

    func testEmptyTitle() {
        let issues = ScheduleValidator.validate(periods: [Fixtures.period("   ", .classPeriod, 9, 0, 10, 0)])
        XCTAssertEqual(issues.count, 1)
        guard case .emptyTitle = issues[0] else { return XCTFail("Expected emptyTitle") }
    }

    func testValidGapsAndAdjacentPeriods() {
        let issues = ScheduleValidator.validate(periods: [
            Fixtures.period("A", .classPeriod, 8, 0, 9, 0),
            Fixtures.period("B", .classPeriod, 9, 0, 10, 0),   // adjacent
            Fixtures.period("C", .classPeriod, 10, 15, 11, 0)  // gap
        ])
        XCTAssertTrue(issues.isEmpty)
    }

    func testOutsideDay() {
        let period = PeriodDefinition(title: "Night", start: ClockTime(hour: 23, minute: 0), end: ClockTime(minutesAfterMidnight: 1500))
        guard case .outsideDay = ScheduleValidator.validate(periods: [period]).first else { return XCTFail("Expected outsideDay") }
    }
}
