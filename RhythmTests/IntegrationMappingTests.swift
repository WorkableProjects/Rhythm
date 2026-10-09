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

    private func snapshot(_ hour: Int, _ minute: Int) -> ScheduleSnapshot {
        let template = SampleTimetable.template()
        let configuration = ScheduleConfiguration(templates: [template], weekdayAssignments: [.friday: template.id])
        let now = friday.date(at: ClockTime(hour: hour, minute: minute), in: calendar)!
        return ScheduleEngine(calendar: calendar).snapshot(at: now, configuration: configuration)
    }

    func testLiveActivityContentInPeriod() throws {
        let state = try XCTUnwrap(LiveActivityCoordinator.contentState(for: snapshot(9, 30)))
        XCTAssertEqual(state.phase, .inPeriod)
        XCTAssertEqual(state.title, "Biology")
        XCTAssertEqual(state.nextTitle, "Algebra II")
        XCTAssertEqual(DeepLink(url: state.deepLink), .period(id: snapshot(9, 30).activePeriod!.id, date: friday))
    }

    func testLiveActivityContentFreeTimeAndUpcoming() throws {
        let free = try XCTUnwrap(LiveActivityCoordinator.contentState(for: snapshot(11, 32)))
        XCTAssertEqual(free.phase, .freeTime)
        XCTAssertEqual(free.title, "World History")

        let early = try XCTUnwrap(LiveActivityCoordinator.contentState(for: snapshot(7, 30)))
        XCTAssertEqual(early.phase, .upcoming)
        XCTAssertNil(LiveActivityCoordinator.contentState(for: snapshot(5, 0)), "Too early to show an activity")
    }

    func testNoLiveActivityAfterSchoolOrWithoutSchedule() {
        XCTAssertNil(LiveActivityCoordinator.contentState(for: snapshot(16, 0)))
        let empty = ScheduleEngine(calendar: calendar).snapshot(at: .now, configuration: .empty)
        XCTAssertNil(LiveActivityCoordinator.contentState(for: empty))
    }

    func testLiveActivityPayloadIsWellUnderFourKilobytes() throws {
        var state = try XCTUnwrap(LiveActivityCoordinator.contentState(for: snapshot(9, 30)))
        state.title = String(repeating: "Advanced Placement Environmental Science ", count: 3)
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
