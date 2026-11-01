import SwiftUI

@main
struct PocketLarderApp: App {
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = "system"

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(colorScheme)
        }
    }
}

private struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            if model.account == nil {
                WelcomeView()
            } else {
                SignedInView()
            }
        }
        // A new stack, so that a pushed `EnterInviteView` can't survive signing in.
        .id(model.account == nil)
        .onOpenURL { model.open($0) }
        .alert(
            signInErrorText(.alreadySignedIn(name: model.alreadySignedInAs ?? "")),
            isPresented: Binding(
                get: { model.alreadySignedInAs != nil },
                set: { if !$0 { model.alreadySignedInAs = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.larder?.sync()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
