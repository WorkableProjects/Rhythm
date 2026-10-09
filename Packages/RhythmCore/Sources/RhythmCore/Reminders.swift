import Foundation

/// Status of a reminder item.
public enum ReminderStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case active
    case snoozed
    case completed

    public var displayName: String {
        switch self {
        case .active: "Active"
        case .snoozed: "Snoozed"
        case .completed: "Completed"
        }
    }
}

/// Priority level for a reminder.
public enum ReminderPriority: String, Hashable, Codable, Sendable, CaseIterable {
    case low, medium, high

    public var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

/// When a reminder fires.
public enum ReminderTrigger: Hashable, Codable, Sendable {
    /// Every time the linked period occurs, `minutes` before it starts (0 = at the start).
    case beforeStart(minutes: Int)
    /// Once, at a specific local date and time (e.g. "Turn in worksheet").
    case oneOff(date: LocalDate, time: ClockTime)
    /// Standalone reminder with optional date and time.
    case standalone(date: LocalDate?, time: ClockTime?)

    public var summary: String {
        switch self {
        case .beforeStart(let minutes) where minutes <= 0:
            return "At start"
        case .beforeStart(let minutes):
            return "\(minutes) min before"
        case .oneOff(let date, let time):
            return "Once on \(date.key) at \(time)"
        case .standalone(let date, let time):
            if let date {
                if let time {
                    return "\(date.key) at \(time)"
                }
                return "Due \(date.key)"
            }
            return "No due date"
        }
    }
}

/// A reminder item, which can be standalone or linked to a schedule period.
public struct ReminderDefinition: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var periodID: UUID?
    public var title: String
    public var body: String?
    public var trigger: ReminderTrigger
    public var isEnabled: Bool
    public var status: ReminderStatus
    public var priority: ReminderPriority
    public var dueDate: LocalDate?
    public var dueTime: ClockTime?
    public var snoozedUntil: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        periodID: UUID? = nil,
        title: String,
        body: String? = nil,
        trigger: ReminderTrigger,
        isEnabled: Bool = true,
        status: ReminderStatus = .active,
        priority: ReminderPriority = .medium,
        dueDate: LocalDate? = nil,
        dueTime: ClockTime? = nil,
        snoozedUntil: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.periodID = periodID
        self.title = title
        self.body = body
        self.trigger = trigger
        self.isEnabled = isEnabled
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.snoozedUntil = snoozedUntil
        self.completedAt = completedAt
    }
}

/// One concrete local notification Rhythm intends to have pending.
public struct PlannedNotification: Hashable, Sendable, Identifiable {
    /// Stable identifier: `rhythm.reminder.<rule>.<date>.<fingerprint>`. The fingerprint changes
    /// when the content or fire time changes, so reconciliation replaces stale requests.
    public var id: String
    public var ruleID: UUID
    public var periodID: UUID
    public var date: LocalDate
    public var title: String
    public var body: String
    public var fireDate: Date
    public var deepLink: URL

    public static let identifierPrefix = "rhythm.reminder."
}

/// Builds the bounded set of notifications Rhythm should have pending. Pure and deterministic.
public struct ReminderPlanner: Sendable {
    public var engine: ScheduleEngine
    /// How many days ahead individual occurrences are scheduled.
    public var horizonDays: Int
    /// iOS keeps at most 64 pending requests per app; stay safely below it.
    public var maximumRequests: Int

    public init(engine: ScheduleEngine, horizonDays: Int = 14, maximumRequests: Int = 60) {
        self.engine = engine
        self.horizonDays = horizonDays
        self.maximumRequests = maximumRequests
    }

    /// Plans notifications after `now`. Occurrences are produced only for periods that actually
    /// appear in the resolved day, so deleted or disabled periods and no-school overrides are
    /// suppressed automatically.
    public func plan(reminders: [ReminderDefinition], configuration: ScheduleConfiguration, now: Date) -> [PlannedNotification] {
        let activeReminders = reminders.filter { $0.isEnabled && $0.status == .active }
        guard !activeReminders.isEmpty else { return [] }

        let today = LocalDate(now, calendar: engine.calendar)
        let days = engine.resolveDays(from: today, count: horizonDays, configuration: configuration)
        let daysByDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })

        var planned: [PlannedNotification] = []
        for reminder in activeReminders {
            switch reminder.trigger {
            case .beforeStart(let minutes):
                guard let periodID = reminder.periodID else { continue }
                for day in days {
                    guard let period = day.periods.first(where: { $0.id == periodID }) else { continue }
                    let fireDate = period.startDate.addingTimeInterval(-TimeInterval(max(0, minutes) * 60))
                    guard fireDate > now else { continue }
                    planned.append(make(reminder, periodID: periodID, periodTitle: period.title, date: day.date, fireDate: fireDate))
                }
            case .oneOff(let date, let time):
                guard let periodID = reminder.periodID else { continue }
                let day = daysByDate[date] ?? engine.resolveDay(date, configuration: configuration)
                guard let period = day.periods.first(where: { $0.id == periodID }),
                      let fireDate = date.date(at: time, in: engine.calendar),
                      fireDate > now else { continue }
                planned.append(make(reminder, periodID: periodID, periodTitle: period.title, date: date, fireDate: fireDate))
            case .standalone(let dateOpt, let timeOpt):
                if let date = dateOpt ?? reminder.dueDate {
                    let time = timeOpt ?? reminder.dueTime ?? ClockTime(hour: 9, minute: 0)
                    if let fireDate = date.date(at: time, in: engine.calendar), fireDate > now {
                        planned.append(make(reminder, periodID: reminder.id, periodTitle: "Reminder", date: date, fireDate: fireDate))
                    }
                }
            }
        }

        planned.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(planned.prefix(maximumRequests))
    }

    private func make(_ reminder: ReminderDefinition, periodID: UUID, periodTitle: String, date: LocalDate, fireDate: Date) -> PlannedNotification {
        let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? periodTitle : reminder.title
        let body: String
        if let custom = reminder.body?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            body = custom
        } else {
            body = periodTitle
        }
        let fingerprint = Self.fingerprint("\(title)|\(body)|\(Int(fireDate.timeIntervalSince1970))|\(periodID)")
        let id = "\(PlannedNotification.identifierPrefix)\(reminder.id.uuidString).\(date.key).\(fingerprint)"
        return PlannedNotification(
            id: id,
            ruleID: reminder.id,
            periodID: periodID,
            date: date,
            title: title,
            body: body,
            fireDate: fireDate,
            deepLink: DeepLink.period(id: periodID, date: date).url
        )
    }

    /// FNV-1a 64-bit hash, stable across launches (unlike `Hasher`).
    static func fingerprint(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

/// Notification permission as Rhythm cares about it.
public enum NotificationAuthorization: String, Sendable, Hashable {
    case notDetermined, denied, authorized, provisional

    public var allowsScheduling: Bool { self == .authorized || self == .provisional }
}

/// Abstraction over `UNUserNotificationCenter` so reconciliation can be tested with a fake.
public protocol NotificationCenterClient: Sendable {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func add(_ notification: PlannedNotification) async throws
    func removePending(identifiers: [String]) async
}

/// The outcome of reconciling pending notifications with the plan.
public struct ReminderReconciliation: Hashable, Sendable {
    public enum Status: String, Sendable, Hashable {
        /// Pending notifications match the plan.
        case scheduled
        /// Reminders are switched off in Rhythm's settings.
        case featureDisabled
        /// The system does not currently allow notifications. Rules are preserved.
        case notAuthorized
    }

    public var status: Status
    public var scheduledCount: Int
    public var added: [String]
    public var removed: [String]
    public var failures: [String]
}

/// Brings pending notification requests in line with the plan. Idempotent: running it twice
/// with the same plan adds and removes nothing the second time.
public struct ReminderReconciler: Sendable {
    public var client: any NotificationCenterClient

    public init(client: any NotificationCenterClient) {
        self.client = client
    }

    public func reconcile(plan: [PlannedNotification], featureEnabled: Bool) async -> ReminderReconciliation {
        let pending = await client.pendingIdentifiers().filter { $0.hasPrefix(PlannedNotification.identifierPrefix) }

        guard featureEnabled else {
            await client.removePending(identifiers: pending)
            return ReminderReconciliation(status: .featureDisabled, scheduledCount: 0, added: [], removed: pending, failures: [])
        }

        let authorization = await client.authorization()
        guard authorization.allowsScheduling else {
            // Rhythm's own rules stay saved; only system requests are cleared, and we never
            // report anything as scheduled.
            await client.removePending(identifiers: pending)
            return ReminderReconciliation(status: .notAuthorized, scheduledCount: 0, added: [], removed: pending, failures: [])
        }

        let planned = Set(plan.map(\.id))
        let pendingSet = Set(pending)
        let toRemove = pending.filter { !planned.contains($0) }
        if !toRemove.isEmpty { await client.removePending(identifiers: toRemove) }

        var added: [String] = []
        var failures: [String] = []
        for notification in plan where !pendingSet.contains(notification.id) {
            do {
                try await client.add(notification)
                added.append(notification.id)
            } catch {
                failures.append(notification.id)
            }
        }

        let scheduledCount = plan.count - failures.count
        return ReminderReconciliation(status: .scheduled, scheduledCount: scheduledCount, added: added, removed: toRemove, failures: failures)
    }
}
