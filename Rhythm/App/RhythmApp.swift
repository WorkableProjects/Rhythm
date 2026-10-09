import AppIntents
import SwiftUI

@main
struct RhythmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel

    init() {
        let model = AppModel(loaded: PersistenceController.shared)
        _model = State(initialValue: model)
        // Lets App Intents reach the same model instance as the UI.
        AppDependencyManager.shared.add(dependency: model)
        model.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.container)
                .preferredColorScheme(model.preferences.appearance.colorScheme)
                .tint(model.preferences.accent == .system ? nil : model.preferences.accent.color)
                .onOpenURL { model.router.handle($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.sceneBecameActive()
            case .background: model.sceneEnteredBackground()
            default: break
            }
        }
    }
}
