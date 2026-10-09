import RhythmCore
import SwiftData
import XCTest
@testable import Rhythm

/// Persistence and mapping tests against an in-memory SwiftData store.
@MainActor
final class RepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: ScheduleRepository!

    override func setUp() async throws {
        container = PersistenceController.load(inMemory: true).container
        repository = ScheduleRepository(context: container.mainContext)
    }

    override func tearDown() async throws {
        repository = nil
        container = nil
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    func testEmptyStoreNeedsSchedule() {
        XCTAssertFalse(repository.configuration().hasAnySchedule)
        let snapshot = ScheduleEngine(calendar: calendar).snapshot(at: .now, configuration: repository.configuration())
        XCTAssertEqual(snapshot.state, .scheduleNeeded)
    }

    func testSampleTimetableIsLabelledAndRemovable() throws {
        repository.insertSampleTimetable()
        try repository.save()

        let configuration = repository.configuration()
        XCTAssertEqual(configuration.templates.count, 1)
        XCTAssertEqual(configuration.weekdayAssignments.count, 5)
        XCTAssertTrue(repository.hasSampleData)

        // Inserting again never duplicates.
        repository.insertSampleTimetable()
        try repository.save()
        XCTAssertEqual(repository.templates().count, 1)

        repository.removeSampleTimetable()
        try repository.save()
        XCTAssertTrue(repository.templates().isEmpty)
        XCTAssertTrue(repository.assignments().isEmpty)
        XCTAssertFalse(repository.hasSampleData)
    }

    func testSampleResolvesThroughEngine() throws {
        repository.insertSampleTimetable()
        try repository.save()
        let friday = LocalDate(year: 2026, month: 10, day: 9)
        let now = friday.date(at: ClockTime(hour: 9, minute: 30), in: calendar)!
        let snapshot = ScheduleEngine(calendar: calendar).snapshot(at: now, configuration: repository.configuration())
        XCTAssertEqual(snapshot.state, .inProgress)
        XCTAssertEqual(snapshot.activePeriod?.title, "Biology")
    }

    func testWeekdayHasOnlyOneTemplate() throws {
        let a = repository.createTemplate(name: "A", weekdays: [.monday])
        let b = repository.createTemplate(name: "B")
        repository.assign(.monday, to: b.id)
        try repository.save()

        XCTAssertEqual(repository.assignments().filter { $0.weekday == .monday }.count, 1)
        XCTAssertEqual(repository.configuration().weekdayAssignments[.monday], b.id)
        XCTAssertTrue(repository.weekdays(assignedTo: a.id).isEmpty)

        repository.assign(.monday, to: nil)
        try repository.save()
        XCTAssertNil(repository.configuration().weekdayAssignments[.monday])
    }

    func testDeletingTemplateCleansUpAssignmentsAndOverrideReferences() throws {
        let template = repository.createTemplate(name: "Regular", weekdays: [.monday, .tuesday])
        let date = LocalDate(year: 2026, month: 10, day: 12)
        repository.setOverride(on: date, kind: .customSchedule, title: "Late", templateID: template.id)
        try repository.save()

        repository.deleteTemplate(template)
        try repository.save()

        XCTAssertTrue(repository.assignments().isEmpty)
        XCTAssertNil(repository.override(on: date)?.templateID)
    }

    func testPeriodUpsertAndReminderMapping() throws {
        let template = repository.createTemplate(name: "Regular", weekdays: [.friday])
        let definition = PeriodDefinition(title: "PE", start: ClockTime(hour: 13, minute: 0), end: ClockTime(hour: 14, minute: 0))
        let period = repository.upsertPeriod(definition, in: template)
        let reminder = ReminderDefinition(periodID: period.id, title: "Bring gym clothes", trigger: .beforeStart(minutes: 15))
        repository.setReminders([reminder], for: period)
        try repository.save()

        XCTAssertEqual(repository.reminderDefinitions(), [reminder])

        var edited = definition
        edited.title = "Physical Education"
        repository.upsertPeriod(edited, in: template)
        repository.setReminders([], for: period)
        try repository.save()

        XCTAssertEqual(repository.configuration().templates[template.id]?.periods.first?.title, "Physical Education")
        XCTAssertTrue(repository.reminders().isEmpty)
    }

    func testDeletingPeriodCascadesToReminders() throws {
        let template = repository.createTemplate(name: "Regular", weekdays: [.friday])
        let period = repository.upsertPeriod(PeriodDefinition(title: "Math", start: ClockTime(hour: 9, minute: 0), end: ClockTime(hour: 10, minute: 0)), in: template)
        repository.setReminders([ReminderDefinition(periodID: period.id, title: "Homework", trigger: .beforeStart(minutes: 5))], for: period)
        try repository.save()

        repository.deletePeriod(period)
        try repository.save()
        XCTAssertTrue(repository.reminders().isEmpty)
    }

    func testOneOverridePerDate() throws {
        let date = LocalDate(year: 2026, month: 10, day: 9)
        repository.setOverride(on: date, kind: .noSchool, title: "Holiday", templateID: nil)
        repository.setOverride(on: date, kind: .noSchool, title: "Teacher Day", templateID: nil)
        try repository.save()
        XCTAssertEqual(repository.overrides().count, 1)
        XCTAssertEqual(repository.override(on: date)?.title, "Teacher Day")
    }

    func testExportImportRoundTripReplacesData() throws {
        repository.insertSampleTimetable()
        repository.addQuicklink(QuicklinkDefinition(title: "Classroom", urlString: "https://classroom.google.com", kind: .website))
        try repository.save()
        let export = repository.makeExport()

        repository.deleteAllData()
        repository.createTemplate(name: "Temporary")
        try repository.save()

        try repository.replaceAll(with: export)
        let reexport = repository.makeExport()
        XCTAssertEqual(Set(reexport.templates.map(\.id)), Set(export.templates.map(\.id)))
        XCTAssertEqual(reexport.quicklinks.map(\.title), ["Classroom"])
        XCTAssertFalse(repository.templates().contains { $0.name == "Temporary" })
    }

    func testDeleteAllData() throws {
        repository.insertSampleTimetable()
        repository.addQuicklink(QuicklinkDefinition(title: "A", urlString: "https://a.com", kind: .website))
        try repository.save()
        repository.deleteAllData()
        try repository.save()
        XCTAssertTrue(repository.templates().isEmpty)
        XCTAssertTrue(repository.quicklinks().isEmpty)
        XCTAssertTrue(repository.assignments().isEmpty)
    }

    func testQuicklinkReorderAndDuplicate() throws {
        let a = repository.addQuicklink(QuicklinkDefinition(title: "A", urlString: "https://a.com", kind: .website))
        let b = repository.addQuicklink(QuicklinkDefinition(title: "B", urlString: "https://b.com", kind: .website))
        try repository.save()
        XCTAssertEqual(repository.quicklinks().map(\.title), ["A", "B"])

        repository.reorderQuicklinks([b, a])
        repository.duplicateQuicklink(a)
        try repository.save()
        XCTAssertEqual(repository.quicklinks().map(\.title), ["B", "A", "A Copy"])
    }
}
