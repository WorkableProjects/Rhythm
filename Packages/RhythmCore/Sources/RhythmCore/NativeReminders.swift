import Foundation

// Rhythm's native reminders: a general-purpose reminders component that works independently of
// any period or schedule. Everything here is pure value logic so the app, the widget extension,
// and App Intents all share one implementation. Due dates use the same wall-clock policy as the
// rest of Rhythm (`LocalDate` + `ClockTime`), so "Friday at 3 PM" keeps its meaning across time
// zones and daylight-saving changes.

// MARK: - Values

public enum ReminderPriority: Int, Codable, CaseIterable, Sendable, Comparable, Identifiable {
    case none = 0, low, medium, high

    public var id: Int { rawValue }

    public static func < (lhs: ReminderPriority, rhs: ReminderPriority) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// The `!` marks shown before a title (empty for `.none`).
    public var marks: String { String(repeating: "!", count: rawValue) }
}

public enum ReminderRepeat: String, Codable, CaseIterable, Sendable, Identifiable {
    case never, daily, weekdays, weekly, biweekly, monthly, yearly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .never: "Never"
        case .daily: "Every Day"
        case .weekdays: "Weekdays"
        case .weekly: "Every Week"
        case .biweekly: "Every 2 Weeks"
        case .monthly: "Every Month"
        case .yearly: "Every Year"
        }
    }

    /// The first occurrence strictly after `date`.
    public func next(after date: LocalDate, calendar: Calendar) -> LocalDate {
        switch self {
        case .never: return date
        case .daily: return date.adding(days: 1, calendar: calendar)
        case .weekly: return date.adding(days: 7, calendar: calendar)
        case .biweekly: return date.adding(days: 14, calendar: calendar)
        case .weekdays:
            var next = date.adding(days: 1, calendar: calendar)
            while [Weekday.saturday, .sunday].contains(next.weekday(in: calendar)) {
                next = next.adding(days: 1, calendar: calendar)
            }
            return next
        case .monthly: return Self.adding(.month, 1, to: date, calendar: calendar)
        case .yearly: return Self.adding(.year, 1, to: date, calendar: calendar)
        }
    }

    private static func adding(_ component: Calendar.Component, _ value: Int, to date: LocalDate, calendar: Calendar) -> LocalDate {
        guard let start = date.startDate(in: calendar),
              let noon = calendar.date(byAdding: .hour, value: 12, to: start),
              let shifted = calendar.date(byAdding: component, value: value, to: noon) else { return date }
        return LocalDate(shifted, calendar: calendar)
    }
}

/// One checklist step inside a reminder.
public struct ReminderSubtask: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

/// A user-created list of reminders (e.g. "Homework").
public struct NativeReminderList: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// One of `RhythmPalette.periodColorKeys`.
    public var colorKey: String
    public var symbolName: String
    public var sortOrder: Int

    public static let defaultID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    public init(id: UUID = UUID(), name: String, colorKey: String = "blue", symbolName: String = "list.bullet", sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.colorKey = colorKey
        self.symbolName = symbolName
        self.sortOrder = sortOrder
    }
}

public struct NativeReminder: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var urlString: String?
    public var listID: UUID
    public var dueDate: LocalDate?
    /// Only meaningful with `dueDate`; `nil` means "all day".
    public var dueTime: ClockTime?
    /// Minutes before `dueTime` to alert (0 = at the due time). Ignored for all-day reminders.
    public var alertMinutesBefore: Int
    public var priority: ReminderPriority
    public var isFlagged: Bool
    public var repeatRule: ReminderRepeat
    public var subtasks: [ReminderSubtask]
    public var isCompleted: Bool
    public var completedAt: Date?
    public var createdAt: Date
    public var sortOrder: Int

    public init(id: UUID = UUID(), title: String, notes: String = "", urlString: String? = nil,
                listID: UUID = NativeReminderList.defaultID, dueDate: LocalDate? = nil, dueTime: ClockTime? = nil,
                alertMinutesBefore: Int = 0, priority: ReminderPriority = .none, isFlagged: Bool = false,
                repeatRule: ReminderRepeat = .never, subtasks: [ReminderSubtask] = [], isCompleted: Bool = false,
                completedAt: Date? = nil, createdAt: Date = .now, sortOrder: Int = 0) {
        self.id = id
        self.title = title
        self.notes = notes
        self.urlString = urlString
        self.listID = listID
        self.dueDate = dueDate
        self.dueTime = dueDate == nil ? nil : dueTime
        self.alertMinutesBefore = alertMinutesBefore
        self.priority = priority
        self.isFlagged = isFlagged
        self.repeatRule = dueDate == nil ? .never : repeatRule
        self.subtasks = subtasks
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    /// The instant the reminder is due. All-day reminders resolve to the very end of their day.
    public func dueInstant(calendar: Calendar) -> Date? {
        guard let dueDate else { return nil }
        if let dueTime { return dueDate.date(at: dueTime, in: calendar) }
        return dueDate.date(at: ClockTime(minutesAfterMidnight: ClockTime.endOfDayMinutes), in: calendar)
    }

    public func isOverdue(now: Date, calendar: Calendar) -> Bool {
        guard !isCompleted, let due = dueInstant(calendar: calendar) else { return false }
        return due < now
    }

    public var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter(\.isDone).count, subtasks.count)
    }

    public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Filters and sections

public enum ReminderFilter: Hashable, Sendable {
    /// Due today or overdue.
    case today
    /// Anything with a due date.
    case scheduled
    case flagged
    case all
    case completed
    case list(UUID)
}

public enum ReminderBucket: Hashable, Sendable {
    case overdue, today, tomorrow
    case upcoming(LocalDate)
    case noDate
}

public struct ReminderSection: Hashable, Sendable, Identifiable {
    public var bucket: ReminderBucket
    public var reminders: [NativeReminder]

    public var id: String {
        switch bucket {
        case .overdue: "overdue"
        case .today: "today"
        case .tomorrow: "tomorrow"
        case .upcoming(let date): "date-\(date.key)"
        case .noDate: "nodate"
        }
    }
}

public enum CompletionOutcome: Hashable, Sendable {
    case completed
    case reopened
    /// A repeating reminder moved to its next occurrence instead of completing.
    case advanced(to: LocalDate)
}

// MARK: - Library

/// Every list and reminder, plus the editing operations on them.
public struct NativeReminderLibrary: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var lists: [NativeReminderList]
    public var reminders: [NativeReminder]

    public init(version: Int = NativeReminderLibrary.currentVersion, lists: [NativeReminderList]? = nil, reminders: [NativeReminder] = []) {
        self.version = version
        self.lists = lists?.isEmpty == false ? lists! : [NativeReminderLibrary.defaultList]
        self.reminders = reminders
    }

    public static var defaultList: NativeReminderList {
        NativeReminderList(id: NativeReminderList.defaultID, name: "Reminders", colorKey: "blue", symbolName: "list.bullet", sortOrder: 0)
    }

    public static let empty = NativeReminderLibrary()

    public var sortedLists: [NativeReminderList] {
        lists.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    public var defaultListID: UUID { sortedLists.first?.id ?? NativeReminderList.defaultID }

    public func list(_ id: UUID) -> NativeReminderList? { lists.first { $0.id == id } }

    public func reminder(_ id: UUID) -> NativeReminder? { reminders.first { $0.id == id } }

    // MARK: Editing

    public mutating func add(_ reminder: NativeReminder) {
        var reminder = reminder
        if list(reminder.listID) == nil { reminder.listID = defaultListID }
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[index] = reminder
        } else {
            reminder.sortOrder = (reminders.map(\.sortOrder).max() ?? -1) + 1
            reminders.append(reminder)
        }
    }

    public mutating func update(_ reminder: NativeReminder) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return add(reminder) }
        var reminder = reminder
        if list(reminder.listID) == nil { reminder.listID = defaultListID }
        reminder.sortOrder = reminders[index].sortOrder
        reminders[index] = reminder
    }

    public mutating func deleteReminders(_ ids: Set<UUID>) {
        reminders.removeAll { ids.contains($0.id) }
    }

    public mutating func deleteCompleted(in listID: UUID? = nil) {
        reminders.removeAll { $0.isCompleted && (listID == nil || $0.listID == listID) }
    }

    public mutating func addList(_ list: NativeReminderList) {
        var list = list
        if let index = lists.firstIndex(where: { $0.id == list.id }) {
            list.sortOrder = lists[index].sortOrder
            lists[index] = list
        } else {
            list.sortOrder = (lists.map(\.sortOrder).max() ?? -1) + 1
            lists.append(list)
        }
    }

    /// Deletes a list and its reminders. The last remaining list can't be deleted.
    @discardableResult
    public mutating func deleteList(_ id: UUID) -> Bool {
        guard lists.count > 1, lists.contains(where: { $0.id == id }) else { return false }
        lists.removeAll { $0.id == id }
        reminders.removeAll { $0.listID == id }
        return true
    }

    /// Completes or reopens a reminder. A repeating reminder with a due date advances to its next
    /// occurrence (and resets its checklist) instead of completing.
    @discardableResult
    public mutating func toggleCompletion(of id: UUID, now: Date, calendar: Calendar) -> CompletionOutcome? {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return nil }
        var reminder = reminders[index]
        if reminder.isCompleted {
            reminder.isCompleted = false
            reminder.completedAt = nil
            reminders[index] = reminder
            return .reopened
        }
        if reminder.repeatRule != .never, let due = reminder.dueDate {
            let today = LocalDate(now, calendar: calendar)
            var next = reminder.repeatRule.next(after: due, calendar: calendar)
            var guardCount = 0
            while next <= today && guardCount < 1_000 {
                next = reminder.repeatRule.next(after: next, calendar: calendar)
                guardCount += 1
            }
            reminder.dueDate = next
            reminder.subtasks = reminder.subtasks.map { var step = $0; step.isDone = false; return step }
            reminders[index] = reminder
            return .advanced(to: next)
        }
        reminder.isCompleted = true
        reminder.completedAt = now
        reminders[index] = reminder
        return .completed
    }

    public mutating func toggleSubtask(_ subtaskID: UUID, in reminderID: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == reminderID }),
              let step = reminders[index].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        reminders[index].subtasks[step].isDone.toggle()
    }

    /// Moves a reminder to the given date at the same time ("Snooze to tomorrow").
    public mutating func reschedule(_ id: UUID, to date: LocalDate, time: ClockTime? = nil) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].dueDate = date
        if let time { reminders[index].dueTime = time }
    }

    // MARK: Querying

    /// Reminders for `filter`, in display order. Search matches title, notes, and checklist text.
    public func items(for filter: ReminderFilter, today: LocalDate, calendar: Calendar, search: String = "") -> [NativeReminder] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches: (NativeReminder) -> Bool = { reminder in
            guard !needle.isEmpty else { return true }
            return reminder.title.lowercased().contains(needle)
                || reminder.notes.lowercased().contains(needle)
                || reminder.subtasks.contains { $0.title.lowercased().contains(needle) }
        }

        switch filter {
        case .completed:
            return reminders.filter { $0.isCompleted && matches($0) }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        case .today:
            return open(matches) { $0.dueDate.map { $0 <= today } ?? false }
        case .scheduled:
            return open(matches) { $0.dueDate != nil }
        case .flagged:
            return open(matches) { $0.isFlagged }
        case .all:
            return open(matches) { _ in true }
        case .list(let id):
            return open(matches) { $0.listID == id }
        }
    }

    public func completedReminders(in listID: UUID, search: String = "") -> [NativeReminder] {
        items(for: .completed, today: LocalDate(year: 1970, month: 1, day: 1), calendar: Calendar(identifier: .gregorian), search: search)
            .filter { $0.listID == listID }
    }

    private func open(_ matches: (NativeReminder) -> Bool, where predicate: (NativeReminder) -> Bool) -> [NativeReminder] {
        reminders.filter { !$0.isCompleted && predicate($0) && matches($0) }.sorted(by: Self.displayOrder)
    }

    /// Due soonest first (all-day before timed on the same day), then priority, then manual order.
    public static func displayOrder(_ lhs: NativeReminder, _ rhs: NativeReminder) -> Bool {
        func key(_ r: NativeReminder) -> (Int, Int, Int, Int, Int) {
            let date = r.dueDate.map { $0.year * 10_000 + $0.month * 100 + $0.day } ?? Int.max
            return (date, r.dueTime?.minutesAfterMidnight ?? -1, -r.priority.rawValue, r.sortOrder, 0)
        }
        let (a, b) = (key(lhs), key(rhs))
        if a != b { return a < b }
        return lhs.createdAt < rhs.createdAt
    }

    public func count(for filter: ReminderFilter, today: LocalDate, calendar: Calendar) -> Int {
        items(for: filter, today: today, calendar: calendar).count
    }

    /// Overdue, today, tomorrow, then one section per later day, then undated.
    public static func sections(for reminders: [NativeReminder], today: LocalDate, calendar: Calendar) -> [ReminderSection] {
        let tomorrow = today.adding(days: 1, calendar: calendar)
        var order: [ReminderBucket] = []
        var grouped: [ReminderBucket: [NativeReminder]] = [:]
        for reminder in reminders {
            let bucket: ReminderBucket
            switch reminder.dueDate {
            case nil: bucket = .noDate
            case let date? where date < today: bucket = .overdue
            case let date? where date == today: bucket = .today
            case let date? where date == tomorrow: bucket = .tomorrow
            case let date?: bucket = .upcoming(date)
            }
            if grouped[bucket] == nil { order.append(bucket) }
            grouped[bucket, default: []].append(reminder)
        }
        return order.map { ReminderSection(bucket: $0, reminders: grouped[$0] ?? []) }
    }
}

// MARK: - Persistence

public enum NativeReminderCodec {
    public static func encode(_ library: NativeReminderLibrary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(library)
    }

    /// `nil` when the data is corrupt or was written by a newer version of Rhythm.
    public static func decode(_ data: Data) -> NativeReminderLibrary? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let library = try? decoder.decode(NativeReminderLibrary.self, from: data),
              library.version <= NativeReminderLibrary.currentVersion else { return nil }
        return library
    }
}

/// Reads and writes the library as one JSON file. The app and the widget extension both use this
/// against the App Group container; `mutate` re-reads before writing so an edit made in one
/// process is never overwritten by a stale copy in the other.
public struct NativeReminderFileStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// A missing file is an empty library. A corrupt or newer file is moved aside (so nothing is
    /// silently destroyed) and an empty library is returned.
    public func load() -> NativeReminderLibrary {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        if let library = NativeReminderCodec.decode(data) { return library }
        let backup = url.deletingPathExtension().appendingPathExtension("unreadable.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
        return .empty
    }

    public func save(_ library: NativeReminderLibrary) throws {
        let data = try NativeReminderCodec.encode(library)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    /// Load, change, save. Returns the saved library.
    @discardableResult
    public func mutate(_ change: (inout NativeReminderLibrary) -> Void) throws -> NativeReminderLibrary {
        var library = load()
        change(&library)
        try save(library)
        return library
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Notifications

public struct ReminderNotificationPlan: Hashable, Sendable, Identifiable {
    public var id: String
    public var reminderID: UUID
    public var title: String
    public var body: String
    public var fireDate: Date
    public var deepLink: URL

    public static let identifierPrefix = "rhythm.task."
}

/// Plans the notifications for open reminders with a due date. Repeating reminders only ever
/// have their next occurrence planned; completing one plans the following occurrence.
public struct NativeReminderPlanner: Sendable {
    public var calendar: Calendar
    /// Kept well under iOS's 64-request cap, which Rhythm's schedule reminders share.
    public var maximumRequests: Int
    /// When an all-day reminder alerts.
    public var allDayAlertTime: ClockTime

    public init(calendar: Calendar, maximumRequests: Int = 20, allDayAlertTime: ClockTime = ClockTime(hour: 9, minute: 0)) {
        self.calendar = calendar
        self.maximumRequests = maximumRequests
        self.allDayAlertTime = allDayAlertTime
    }

    public func plan(library: NativeReminderLibrary, now: Date) -> [ReminderNotificationPlan] {
        var planned: [ReminderNotificationPlan] = []
        for reminder in library.reminders where !reminder.isCompleted {
            guard let date = reminder.dueDate else { continue }
            let fire: Date?
            if let time = reminder.dueTime {
                fire = date.date(at: time, in: calendar).map { $0.addingTimeInterval(-TimeInterval(max(0, reminder.alertMinutesBefore) * 60)) }
            } else {
                fire = date.date(at: allDayAlertTime, in: calendar)
            }
            guard let fireDate = fire, fireDate > now else { continue }

            let title = reminder.trimmedTitle.isEmpty ? "Reminder" : reminder.trimmedTitle
            let listName = library.list(reminder.listID)?.name ?? ""
            let notes = reminder.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = notes.isEmpty ? listName : notes
            let fingerprint = ReminderPlanner.fingerprint("\(title)|\(body)|\(Int(fireDate.timeIntervalSince1970))")
            planned.append(ReminderNotificationPlan(
                id: "\(ReminderNotificationPlan.identifierPrefix)\(reminder.id.uuidString).\(fingerprint)",
                reminderID: reminder.id, title: title, body: body, fireDate: fireDate,
                deepLink: DeepLink.reminder(id: reminder.id).url))
        }
        planned.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(planned.prefix(maximumRequests))
    }
}

// MARK: - Quick add

/// Turns a typed phrase such as "Turn in essay tomorrow 3pm !high #Homework" into a reminder's
/// fields. Recognised words are removed from the title; everything else is kept as typed.
public struct ReminderQuickAdd: Hashable, Sendable {
    public var title: String
    public var dueDate: LocalDate?
    public var dueTime: ClockTime?
    public var priority: ReminderPriority
    public var isFlagged: Bool
    public var listName: String?

    private static let weekdayNames: [String: Weekday] = [
        "sunday": .sunday, "monday": .monday, "tuesday": .tuesday, "tue": .tuesday, "tues": .tuesday,
        "wednesday": .wednesday, "thursday": .thursday, "thu": .thursday, "thur": .thursday, "thurs": .thursday,
        "friday": .friday, "fri": .friday, "saturday": .saturday
    ]

    public static func parse(_ text: String, today: LocalDate, calendar: Calendar) -> ReminderQuickAdd {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var consumed = Set<Int>()
        var result = ReminderQuickAdd(title: "", dueDate: nil, dueTime: nil, priority: .none, isFlagged: false, listName: nil)

        func lower(_ index: Int) -> String? {
            words.indices.contains(index) ? words[index].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.")) : nil
        }

        var index = 0
        while index < words.count {
            if consumed.contains(index) {
                index += 1
                continue
            }
            let word = lower(index) ?? ""
            let previous = lower(index - 1)
            let previousUnused = !consumed.contains(index - 1)

            if word.hasPrefix("#"), word.count > 1 {
                result.listName = String(words[index].dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: ",."))
                consumed.insert(index)
            } else if let priority = priority(from: word) {
                result.priority = priority
                consumed.insert(index)
            } else if word == "!flag" || word == "!flagged" {
                result.isFlagged = true
                consumed.insert(index)
            } else if result.dueDate == nil, let date = relativeDate(word, next: lower(index + 1), after: lower(index + 2), today: today, calendar: calendar) {
                result.dueDate = date.date
                consumed.formUnion((index..<(index + date.words)))
                if date.word == "tonight", result.dueTime == nil { result.dueTime = ClockTime(hour: 19, minute: 0) }
                if ["on", "by", "due"].contains(previous ?? ""), previousUnused { consumed.insert(index - 1) }
            } else if result.dueTime == nil, let time = clockTime(word, next: lower(index + 1)) {
                result.dueTime = time.time
                consumed.formUnion((index..<(index + time.words)))
                if ["at", "by"].contains(previous ?? ""), previousUnused { consumed.insert(index - 1) }
            }
            index += 1
        }

        // A time with no date means today (or tomorrow if it has already passed isn't knowable
        // here, so today).
        if result.dueTime != nil, result.dueDate == nil { result.dueDate = today }

        let title = words.indices.filter { !consumed.contains($0) }.map { words[$0] }.joined(separator: " ")
        if title.isEmpty {
            result.title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            result.dueDate = nil
            result.dueTime = nil
        } else {
            result.title = title
        }
        return result
    }

    private static func priority(from word: String) -> ReminderPriority? {
        switch word {
        case "!", "!low": .low
        case "!!", "!med", "!medium": .medium
        case "!!!", "!high", "!urgent": .high
        default: nil
        }
    }

    private struct DateMatch {
        var date: LocalDate
        var words: Int
        var word: String
    }

    private static func relativeDate(_ word: String, next: String?, after: String?, today: LocalDate, calendar: Calendar) -> DateMatch? {
        switch word {
        case "today", "tonight":
            return DateMatch(date: today, words: 1, word: word)
        case "tomorrow", "tmrw", "tmr":
            return DateMatch(date: today.adding(days: 1, calendar: calendar), words: 1, word: word)
        case "in":
            guard let next, let count = Int(next), (1...365).contains(count), let unit = after else { return nil }
            switch unit {
            case "day", "days": return DateMatch(date: today.adding(days: count, calendar: calendar), words: 3, word: word)
            case "week", "weeks": return DateMatch(date: today.adding(days: count * 7, calendar: calendar), words: 3, word: word)
            default: return nil
            }
        case "next":
            if next == "week" { return DateMatch(date: today.adding(days: 7, calendar: calendar), words: 2, word: word) }
            if let next, let weekday = weekdayNames[next] {
                return DateMatch(date: nextOccurrence(of: weekday, after: today, calendar: calendar), words: 2, word: word)
            }
            return nil
        default:
            if let weekday = weekdayNames[word] {
                return DateMatch(date: nextOccurrence(of: weekday, after: today, calendar: calendar), words: 1, word: word)
            }
            return nil
        }
    }

    /// The next `weekday` strictly after `today` (typing "friday" on a Friday means next week).
    private static func nextOccurrence(of weekday: Weekday, after today: LocalDate, calendar: Calendar) -> LocalDate {
        var date = today.adding(days: 1, calendar: calendar)
        for _ in 0..<7 where date.weekday(in: calendar) != weekday { date = date.adding(days: 1, calendar: calendar) }
        return date
    }

    private struct TimeMatch {
        var time: ClockTime
        var words: Int
    }

    /// `3pm`, `3:30pm`, `3 pm`, `15:00`, `noon`.
    private static func clockTime(_ word: String, next: String?) -> TimeMatch? {
        if word == "noon" { return TimeMatch(time: ClockTime(hour: 12, minute: 0), words: 1) }

        var body = word
        var meridiem: String?
        var words = 1
        if body.hasSuffix("am") || body.hasSuffix("pm") {
            meridiem = String(body.suffix(2))
            body.removeLast(2)
        } else if let next, next == "am" || next == "pm", Int(body.split(separator: ":").first ?? "") != nil {
            meridiem = next
            words = 2
        }

        let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              var hour = Int(parts[0]) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
        guard (0..<60).contains(minute) else { return nil }

        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm", hour < 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        } else {
            // Bare numbers are not times; only a 24-hour `H:mm` is.
            guard parts.count == 2, (0...23).contains(hour) else { return nil }
        }
        return TimeMatch(time: ClockTime(hour: hour, minute: minute), words: words)
    }
}
