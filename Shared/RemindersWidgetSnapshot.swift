import Foundation

public struct RemindersWidgetItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var body: String?
    public var periodTitle: String?
    public var statusRaw: String
    public var priorityRaw: String
    public var formattedDueDate: String?
    public var snoozedUntilDate: Date?

    public init(
        id: UUID,
        title: String,
        body: String? = nil,
        periodTitle: String? = nil,
        statusRaw: String = "active",
        priorityRaw: String = "medium",
        formattedDueDate: String? = nil,
        snoozedUntilDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.periodTitle = periodTitle
        self.statusRaw = statusRaw
        self.priorityRaw = priorityRaw
        self.formattedDueDate = formattedDueDate
        self.snoozedUntilDate = snoozedUntilDate
    }

    public var isCompleted: Bool { statusRaw == "completed" }
    public var isSnoozed: Bool { statusRaw == "snoozed" }
}

public struct RemindersWidgetSnapshot: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    public var accentKey: String
    public var items: [RemindersWidgetItem]

    public init(
        version: Int = RemindersWidgetSnapshot.currentVersion,
        generatedAt: Date = .now,
        accentKey: String = "system",
        items: [RemindersWidgetItem] = []
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.accentKey = accentKey
        self.items = items
    }
}

public enum RemindersWidgetSnapshotCodec {
    public static func encode(_ snapshot: RemindersWidgetSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data?) -> Result<RemindersWidgetSnapshot, WidgetSnapshotError> {
        guard let data, !data.isEmpty else { return .failure(.missing) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(RemindersWidgetSnapshot.self, from: data) else { return .failure(.corrupt) }
        return .success(snapshot)
    }
}
