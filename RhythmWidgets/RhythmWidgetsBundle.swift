import SwiftUI
import WidgetKit

@main
struct RhythmWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
        RemindersWidget()
        AddReminderWidget()
        RhythmLiveActivityWidget()
    }
}
