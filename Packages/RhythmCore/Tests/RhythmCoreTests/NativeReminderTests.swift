import XCTest
@testable import RhythmCore

final class NativeReminderTests: XCTestCase {
    private let calendar = Fixtures.calendar()
    private var today: LocalDate { Fixtures.friday }
    private var now: Date { Fixtures.instant(Fixtures.friday, 10, 0) }

    private func makeLibrary(_ reminders: [NativeReminder]) -> NativeReminderLibrary {
        var library = NativeReminderLibrary()
        reminders.forEach { library.add($0) }
        return library
    }

    // MARK: Library

    func testDefaultListAlwaysExistsAndLastListCannotBeDeleted() {
        var library = NativeReminderLibrary()
        XCTAssertEqual(library.lists.count, 1)
        XCTAssertFalse(library.deleteList(library.defaultListID))
        let homework = NativeReminderList(name: "Homework")
        library.addList(homework)
        XCTAssertTrue(library.deleteList(homework.id))
        XCTAssertEqual(library.lists.count, 1)
    }

    func testDeletingListDeletesItsReminders() {
        var library = NativeReminderLibrary()
        let other = NativeReminderList(name: "Other")
        library.addList(other)
        library.add(NativeReminder(title: "A", listID: other.id))
        library.add(NativeReminder(title: "B"))
        library.deleteList(other.id)
        XCTAssertEqual(library.reminders.map(\.title), ["B"])
    }

    func testUnknownListFallsBackToDefault() {
        var library = NativeReminderLibrary()
        library.add(NativeReminder(title: "A", listID: UUID()))
        XCTAssertEqual(library.reminders[0].listID, library.defaultListID)
    }

    func testTimeAndRepeatAreDroppedWithoutDueDate() {
        let reminder = NativeReminder(title: "A", dueDate: nil, dueTime: ClockTime(hour: 9, minute: 0), repeatRule: .daily)
        XCTAssertNil(reminder.dueTime)
        XCTAssertEqual(reminder.repeatRule, .never)
    }

    // MARK: Completion

    func testCompleteAndReopen() {
        var library = makeLibrary([NativeReminder(title: "A")])
        let id = library.reminders[0].id
        XCTAssertEqual(library.toggleCompletion(of: id, now: now, calendar: calendar), .completed)
        XCTAssertTrue(library.reminders[0].isCompleted)
        XCTAssertEqual(library.reminders[0].completedAt, now)
        XCTAssertEqual(library.toggleCompletion(of: id, now: now, calendar: calendar), .reopened)
        XCTAssertFalse(library.reminders[0].isCompleted)
        XCTAssertNil(library.toggleCompletion(of: UUID(), now: now, calendar: calendar))
    }

    func testRepeatingReminderAdvancesAndResetsChecklist() {
        var library = makeLibrary([NativeReminder(title: "Practice", dueDate: today, repeatRule: .daily,
                                              subtasks: [ReminderSubtask(title: "Scales", isDone: true)])])
        let id = library.reminders[0].id
        let outcome = library.toggleCompletion(of: id, now: now, calendar: calendar)
        XCTAssertEqual(outcome, .advanced(to: Fixtures.saturday))
        XCTAssertFalse(library.reminders[0].isCompleted)
        XCTAssertEqual(library.reminders[0].dueDate, Fixtures.saturday)
        XCTAssertFalse(library.reminders[0].subtasks[0].isDone)
    }

    func testOverdueRepeatingReminderSkipsToTheFuture() {
        let longAgo = today.adding(days: -10, calendar: calendar)
        var library = makeLibrary([NativeReminder(title: "Trash", dueDate: longAgo, repeatRule: .weekly)])
        library.toggleCompletion(of: library.reminders[0].id, now: now, calendar: calendar)
        let next = library.reminders[0].dueDate!
        XCTAssertGreaterThan(next, today)
        XCTAssertLessThanOrEqual(next, today.adding(days: 7, calendar: calendar))
        XCTAssertEqual(next.weekday(in: calendar), longAgo.weekday(in: calendar))
    }

    func testWeekdaysRepeatSkipsWeekend() {
        XCTAssertEqual(ReminderRepeat.weekdays.next(after: Fixtures.friday, calendar: calendar),
                       LocalDate(year: 2026, month: 10, day: 12))
    }

    func testMonthlyRepeatClampsToShortMonths() {
        let jan31 = LocalDate(year: 2026, month: 1, day: 31)
        XCTAssertEqual(ReminderRepeat.monthly.next(after: jan31, calendar: calendar), LocalDate(year: 2026, month: 2, day: 28))
    }

    func testSubtaskToggle() {
        var library = makeLibrary([NativeReminder(title: "A", subtasks: [ReminderSubtask(title: "One")])])
        let reminder = library.reminders[0]
        library.toggleSubtask(reminder.subtasks[0].id, in: reminder.id)
        XCTAssertEqual(library.reminders[0].subtaskProgress.done, 1)
    }

    // MARK: Filters

    func testSmartFilters() {
        let yesterday = today.adding(days: -1, calendar: calendar)
        let tomorrow = today.adding(days: 1, calendar: calendar)
        var library = makeLibrary([
            NativeReminder(title: "Overdue", dueDate: yesterday),
            NativeReminder(title: "Today", dueDate: today),
            NativeReminder(title: "Tomorrow", dueDate: tomorrow),
            NativeReminder(title: "Flag", isFlagged: true),
            NativeReminder(title: "Plain"),
            NativeReminder(title: "Done", dueDate: today)
        ])
        library.toggleCompletion(of: library.reminders[5].id, now: now, calendar: calendar)

        func titles(_ filter: ReminderFilter) -> [String] {
            library.items(for: filter, today: today, calendar: calendar).map(\.title)
        }
        XCTAssertEqual(titles(.today), ["Overdue", "Today"])
        XCTAssertEqual(titles(.scheduled), ["Overdue", "Today", "Tomorrow"])
        XCTAssertEqual(titles(.flagged), ["Flag"])
        XCTAssertEqual(titles(.all).count, 5)
        XCTAssertEqual(titles(.completed), ["Done"])
        XCTAssertEqual(titles(.list(library.defaultListID)).count, 5)
        XCTAssertEqual(library.count(for: .today, today: today, calendar: calendar), 2)
    }

    func testDisplayOrderUsesTimeThenPriority() {
        let library = makeLibrary([
            NativeReminder(title: "Low late", dueDate: today, dueTime: ClockTime(hour: 15, minute: 0)),
            NativeReminder(title: "All day", dueDate: today),
            NativeReminder(title: "High 8", dueDate: today, dueTime: ClockTime(hour: 8, minute: 0), priority: .high),
            NativeReminder(title: "Undated")
        ])
        XCTAssertEqual(library.items(for: .all, today: today, calendar: calendar).map(\.title),
                       ["All day", "High 8", "Low late", "Undated"])
    }

    func testSearchMatchesTitleNotesAndChecklist() {
        let library = makeLibrary([
            NativeReminder(title: "Essay", notes: "Cite sources"),
            NativeReminder(title: "Lab", subtasks: [ReminderSubtask(title: "Bring goggles")]),
            NativeReminder(title: "Other")
        ])
        func search(_ text: String) -> [String] {
            library.items(for: .all, today: today, calendar: calendar, search: text).map(\.title)
        }
        XCTAssertEqual(search("cite"), ["Essay"])
        XCTAssertEqual(search("GOGGLES"), ["Lab"])
        XCTAssertEqual(search("  "), ["Essay", "Lab", "Other"])
    }

    func testSections() {
        let reminders = [
            NativeReminder(title: "O", dueDate: today.adding(days: -2, calendar: calendar)),
            NativeReminder(title: "T", dueDate: today),
            NativeReminder(title: "M", dueDate: today.adding(days: 1, calendar: calendar)),
            NativeReminder(title: "L", dueDate: today.adding(days: 5, calendar: calendar)),
            NativeReminder(title: "N")
        ]
        let sections = NativeReminderLibrary.sections(for: reminders, today: today, calendar: calendar)
        XCTAssertEqual(sections.map(\.id), ["overdue", "today", "tomorrow", "date-2026-10-14", "nodate"])
    }

    func testOverdueUsesDueTimeForTimedReminders() {
        let timed = NativeReminder(title: "A", dueDate: today, dueTime: ClockTime(hour: 9, minute: 0))
        let allDay = NativeReminder(title: "B", dueDate: today)
        XCTAssertTrue(timed.isOverdue(now: now, calendar: calendar))
        XCTAssertFalse(allDay.isOverdue(now: now, calendar: calendar))
    }

    // MARK: Persistence

    func testCodecRoundTripAndVersionGuard() throws {
        let original = makeLibrary([NativeReminder(title: "A", notes: "n", dueDate: today, dueTime: ClockTime(hour: 7, minute: 5),
                                               priority: .high, repeatRule: .weekly, createdAt: Date(timeIntervalSince1970: 1_000))])
        let decoded = NativeReminderCodec.decode(try NativeReminderCodec.encode(original))
        XCTAssertEqual(decoded, original)

        var newer = original
        newer.version = NativeReminderLibrary.currentVersion + 1
        XCTAssertNil(NativeReminderCodec.decode(try NativeReminderCodec.encode(newer)))
        XCTAssertNil(NativeReminderCodec.decode(Data("nope".utf8)))
    }

    func testFileStoreMutateAndCorruptFileRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rhythm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeReminderFileStore(url: directory.appendingPathComponent("Reminders.json"))

        XCTAssertTrue(store.load().reminders.isEmpty)
        try store.mutate { $0.add(NativeReminder(title: "A")) }
        try store.mutate { $0.add(NativeReminder(title: "B")) }
        XCTAssertEqual(store.load().reminders.map(\.title), ["A", "B"])

        try Data("garbage".utf8).write(to: store.url)
        XCTAssertTrue(store.load().reminders.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Reminders.unreadable.json").path))
    }

    // MARK: Notifications

    func testPlannerSchedulesOnlyFutureOpenDatedReminders() {
        let tomorrow = today.adding(days: 1, calendar: calendar)
        var library = makeLibrary([
            NativeReminder(title: "Timed", dueDate: tomorrow, dueTime: ClockTime(hour: 15, minute: 0), alertMinutesBefore: 30),
            NativeReminder(title: "All day", dueDate: tomorrow),
            NativeReminder(title: "Past", dueDate: today, dueTime: ClockTime(hour: 8, minute: 0)),
            NativeReminder(title: "Undated"),
            NativeReminder(title: "Done", dueDate: tomorrow)
        ])
        library.toggleCompletion(of: library.reminders[4].id, now: now, calendar: calendar)
        let plan = NativeReminderPlanner(calendar: calendar).plan(library: library, now: now)
        XCTAssertEqual(plan.map(\.title), ["All day", "Timed"])
        XCTAssertEqual(plan[0].fireDate, Fixtures.instant(tomorrow, 9, 0))
        XCTAssertEqual(plan[1].fireDate, Fixtures.instant(tomorrow, 14, 30))
        XCTAssertTrue(plan.allSatisfy { $0.id.hasPrefix(ReminderNotificationPlan.identifierPrefix) })
        XCTAssertEqual(DeepLink(url: plan[0].deepLink), .reminder(id: library.reminders[1].id))
    }

    func testPlannerIsBounded() {
        let reminders = (0..<40).map { NativeReminder(title: "R\($0)", dueDate: today.adding(days: $0 + 1, calendar: calendar)) }
        let plan = NativeReminderPlanner(calendar: calendar, maximumRequests: 20).plan(library: makeLibrary(reminders), now: now)
        XCTAssertEqual(plan.count, 20)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
    }

    // MARK: Quick add

    private func parse(_ text: String) -> ReminderQuickAdd {
        ReminderQuickAdd.parse(text, today: today, calendar: calendar)
    }

    func testQuickAddTomorrowWithTime() {
        let result = parse("Turn in essay tomorrow at 3pm")
        XCTAssertEqual(result.title, "Turn in essay")
        XCTAssertEqual(result.dueDate, Fixtures.saturday)
        XCTAssertEqual(result.dueTime, ClockTime(hour: 15, minute: 0))
    }

    func testQuickAddPriorityListAndWeekday() {
        let result = parse("Read chapter 4 friday !high #Homework")
        XCTAssertEqual(result.title, "Read chapter 4")
        XCTAssertEqual(result.dueDate, LocalDate(year: 2026, month: 10, day: 16)) // next Friday, not today
        XCTAssertEqual(result.priority, .high)
        XCTAssertEqual(result.listName, "Homework")
    }

    func testQuickAddRelativeAndClockForms() {
        XCTAssertEqual(parse("Quiz in 3 days").dueDate, LocalDate(year: 2026, month: 10, day: 12))
        XCTAssertEqual(parse("Quiz in 3 days").title, "Quiz")
        XCTAssertEqual(parse("Call mom 12:30am").dueTime, ClockTime(hour: 0, minute: 30))
        XCTAssertEqual(parse("Call mom 12pm").dueTime, ClockTime(hour: 12, minute: 0))
        XCTAssertEqual(parse("Meet 15:45").dueTime, ClockTime(hour: 15, minute: 45))
        XCTAssertEqual(parse("Lunch noon").dueTime, ClockTime(hour: 12, minute: 0))
        XCTAssertEqual(parse("Study next week").dueDate, LocalDate(year: 2026, month: 10, day: 16))
        XCTAssertEqual(parse("Do it tonight").dueTime, ClockTime(hour: 19, minute: 0))
    }

    func testQuickAddTimeAloneMeansToday() {
        let result = parse("Submit form 4pm")
        XCTAssertEqual(result.dueDate, today)
        XCTAssertEqual(result.title, "Submit form")
    }

    func testQuickAddLeavesPlainNumbersAndPlainTextAlone() {
        let result = parse("Chapter 5 problems 1 to 20")
        XCTAssertEqual(result.title, "Chapter 5 problems 1 to 20")
        XCTAssertNil(result.dueDate)
        XCTAssertNil(result.dueTime)
        XCTAssertEqual(result.priority, .none)
    }

    func testQuickAddKeepsOriginalTextWhenNothingIsLeft() {
        let result = parse("tomorrow")
        XCTAssertEqual(result.title, "tomorrow")
        XCTAssertNil(result.dueDate)
    }
}
