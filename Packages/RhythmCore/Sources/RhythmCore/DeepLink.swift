import Foundation

/// Rhythm's own URL routes (`rhythm://…`), used by widgets, the Live Activity,
/// notifications, and App Intents.
public enum DeepLink: Hashable, Sendable {
    case today(date: LocalDate?)
    case period(id: UUID, date: LocalDate?)
    case schedule(date: LocalDate?)
    case quicklinks
    case settings
    /// The native Reminders tab.
    case reminders
    /// One native reminder, opened in its editor.
    case reminder(id: UUID)
    /// Starts a new native reminder.
    case newReminder

    public static let scheme = "rhythm"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        var dateItem: LocalDate?
        switch self {
        case .today(let date):
            components.host = "today"
            dateItem = date
        case .period(let id, let date):
            components.host = "period"
            components.path = "/" + id.uuidString
            dateItem = date
        case .schedule(let date):
            components.host = "schedule"
            dateItem = date
        case .quicklinks:
            components.host = "quicklinks"
        case .settings:
            components.host = "settings"
        case .reminders:
            components.host = "reminders"
        case .reminder(let id):
            components.host = "reminder"
            components.path = "/" + id.uuidString
        case .newReminder:
            components.host = "newreminder"
        }
        if let dateItem {
            components.queryItems = [URLQueryItem(name: "date", value: dateItem.key)]
        }
        return components.url ?? URL(string: "rhythm://today")!
    }

    /// Parses a Rhythm URL. Unknown or malformed URLs return `nil`.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let date = components.queryItems?.first { $0.name == "date" }?.value.flatMap(LocalDate.init(key:))
        switch components.host?.lowercased() {
        case "today", nil:
            self = .today(date: date)
        case "period":
            let idString = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let id = UUID(uuidString: idString) else { return nil }
            self = .period(id: id, date: date)
        case "schedule":
            self = .schedule(date: date)
        case "quicklinks":
            self = .quicklinks
        case "settings":
            self = .settings
        case "reminders":
            self = .reminders
        case "reminder":
            let idString = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let id = UUID(uuidString: idString) else { return nil }
            self = .reminder(id: id)
        case "newreminder":
            self = .newReminder
        default:
            return nil
        }
    }
}
