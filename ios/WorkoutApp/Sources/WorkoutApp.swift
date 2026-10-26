import SwiftUI
import WorkoutUI

@main
struct WorkoutApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if !model.isOnboarded {
                OnboardingView()
            } else if let session = model.activeSession {
                if session.started { DeckView(session: session) } else { DeckOverview(session: session, confirming: true) }
            } else {
                HomeView()
            }
        }
        // Re-identified per theme so every static `Theme.*` read is re-evaluated when the user switches; the
        // Profile sheet lives out here so it survives the switch and shows the new look live.
        .id(model.theme)
        .environment(\.theme, model.theme.spec)
        .preferredColorScheme(model.theme.spec.colorScheme)
        .tint(model.theme.spec.colors.tint)
        .sheet(isPresented: $model.showSettings) {
            SettingsView().id(model.theme).environment(\.theme, model.theme.spec).preferredColorScheme(model.theme.spec.colorScheme).tint(model.theme.spec.colors.tint)
        }
        .animation(Theme.Motion.spring, value: model.isOnboarded)
        .animation(Theme.Motion.spring, value: model.activeSession?.id)
        .animation(Theme.Motion.spring, value: model.activeSession?.started)
        .task { await model.syncIfPossible() }
    }
}
