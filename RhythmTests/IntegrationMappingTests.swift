import RhythmCore
import XCTest
@testable import Rhythm

/// Tests for the mapping between schedule state and system integrations.
@MainActor
final class IntegrationMappingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private let friday = LocalDate(year: 2026, month: 10, day: 9)

    private var day: ResolvedDay {
        let template = SampleTimetable.template()
        let configuration = ScheduleConfiguration(templates: [template], weekdayAssignments: [.friday: template.id])
        return ScheduleEngine(calendar: calendar).resolveDay(friday, configuration: configuration)
    }

    private func activityState(_ hour: Int, _ minute: Int) -> RhythmActivityAttributes.ContentState? {
        let now = friday.date(at: ClockTime(hour: hour, minute: minute), in: calendar)!
        return ScheduleSegments.liveFrame(at: now, day: day).map(LiveActivityCoordinator.contentState(for:))
    }

    func testLiveActivityContentInPeriodCarriesFollowingSegment() throws {
        let state = try XCTUnwrap(activityState(9, 30))
        XCTAssertEqual(state.current.kind, .period)
        XCTAssertEqual(state.current.title, "Biology")
        // Biology ends 9:55; Algebra II starts 10:00, so a passing period follows.
        XCTAssertEqual(state.following?.kind, .passing)
        XCTAssertEqual(state.following?.title, "Algebra II")
        let biology = try XCTUnwrap(day.periods.first { $0.title == "Biology" })
        XCTAssertEqual(DeepLink(url: state.deepLink), .period(id: biology.id, date: friday))
    }

    func testLiveActivityContentDuringPassingAndBeforeSchool() throws {
        let passing = try XCTUnwrap(activityState(9, 57))
        XCTAssertEqual(passing.current.kind, .passing)
        XCTAssertEqual(passing.current.title, "Algebra II")
        XCTAssertEqual(passing.following?.kind, .period)

        let early = try XCTUnwrap(activityState(7, 30))
        XCTAssertEqual(early.current.kind, .beforeSchool)
        XCTAssertNil(activityState(5, 0), "Too early to show an activity")
    }

    func testNoLiveActivityAfterSchool() {
        XCTAssertNil(activityState(16, 0))
    }

    func testLiveActivityPayloadIsWellUnderFourKilobytes() throws {
        var state = try XCTUnwrap(activityState(9, 30))
        state.current.title = String(repeating: "Advanced Placement Environmental Science ", count: 3)
        let data = try JSONEncoder().encode(state)
        XCTAssertLessThan(data.count, 4096)
    }

    func testRouterHandlesDeepLinks() {
        let router = AppRouter()
        let id = UUID()
        router.handle(DeepLink.period(id: id, date: friday).url)
        XCTAssertEqual(router.selectedTab, .today)
        XCTAssertEqual(router.todayDate, friday)
        XCTAssertEqual(router.presentedPeriod?.periodID, id)

        router.handle(URL(string: "rhythm://quicklinks")!)
        XCTAssertEqual(router.selectedTab, .quicklinks)

        router.handle(URL(string: "rhythm://settings")!)
        XCTAssertTrue(router.isShowingSettings)

        router.handle(URL(string: "https://example.com")!)
        XCTAssertTrue(router.isShowingSettings, "Unknown URLs are ignored")
    }
}
