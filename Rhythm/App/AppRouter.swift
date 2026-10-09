import Foundation
import Observation
import RhythmCore

enum AppTab: Hashable {
    case today, reminders, schedule, quicklinks
}

/// A period presented as a detail sheet, e.g. from a widget, notification, or timeline tap.
struct PeriodPresentation: Identifiable, Hashable {
    var periodID: UUID
    var date: LocalDate
    var id: String { "\(periodID.uuidString)-\(date.key)" }
}

/// Navigation state shared by deep links, App Intents, and views.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    /// The day Today is showing; `nil` means "live today".
    var todayDate: LocalDate? = nil
    /// The day the Schedule tab is showing; `nil` means today.
    var scheduleDate: LocalDate? = nil
    var presentedPeriod: PeriodPresentation? = nil
    var isShowingSettings = false
    /// Asks the Schedule tab to present the new-schedule sheet.
    var isCreatingTemplate = false
    /// Asks the Schedule tab to open this template's editor.
    var pendingTemplateID: UUID? = nil
    /// Asks the Reminders tab to present the new-reminder sheet.
    var isCreatingReminder = false
    /// Asks the Reminders tab to open this reminder in its editor.
    var pendingReminderID: UUID? = nil
    /// Set when a reminder list is deleted so any screen showing it can close.
    var reminderListDeleted: UUID? = nil

    func handle(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        handle(link)
    }

    func handle(_ link: DeepLink) {
        isShowingSettings = false
        switch link {
        case .today(let date):
            selectedTab = .today
            todayDate = date
        case .period(let id, let date):
            selectedTab = .today
            todayDate = date
            if let date { presentedPeriod = PeriodPresentation(periodID: id, date: date) }
        case .schedule(let date):
            selectedTab = .schedule
            scheduleDate = date
        case .quicklinks:
            selectedTab = .quicklinks
        case .settings:
            isShowingSettings = true
        case .reminders:
            selectedTab = .reminders
        case .reminder(let id):
            selectedTab = .reminders
            pendingReminderID = id
        case .newReminder:
            selectedTab = .reminders
            isCreatingReminder = true
        }
    }
}
