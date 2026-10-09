import SwiftUI

/// Shows onboarding on first run, otherwise the three-tab app. Settings is a sheet reached from
/// a toolbar button rather than a fourth tab.
struct RootView: View {
    @Environment(AppModel.self) private var model

    private var needsOnboarding: Bool {
        !model.preferences.hasCompletedOnboarding && !model.configuration.hasAnySchedule
    }

    var body: some View {
        @Bindable var router = model.router
        Group {
            if needsOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                TabView(selection: $router.selectedTab) {
                    Tab("Today", systemImage: "clock", value: AppTab.today) {
                        TodayView()
                    }
                    Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                        ScheduleView()
                    }
                    Tab("Quicklinks", systemImage: "square.grid.2x2", value: AppTab.quicklinks) {
                        QuicklinksView()
                    }
                }
            }
        }
        .sheet(isPresented: $router.isShowingSettings) {
            SettingsView()
        }
        .alert("Data Not Saved", isPresented: Binding(get: { model.recoveryMessage != nil }, set: { if !$0 { model.recoveryMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.recoveryMessage ?? "")
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.saveError ?? "")
        }
    }
}
