import SwiftUI
import WorkoutUI

@main
struct WorkoutApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.Colors.brass)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.isOnboarded {
                OnboardingView()
            } else if let session = model.activeSession {
                DeckView(session: session)
            } else {
                HomeView()
            }
        }
        .animation(Theme.Motion.spring, value: model.isOnboarded)
        .animation(Theme.Motion.spring, value: model.activeSession?.id)
        .task { await model.syncIfPossible() }
    }
}
