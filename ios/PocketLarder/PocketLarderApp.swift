import SwiftUI

@main
struct PocketLarderApp: App {
    @State private var model: AppModel = {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "fixture") == "household" { return .fixture() }
        #endif
        return AppModel()
    }()
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
            if let larder = model.larder {
                MainView(larder: larder)
            } else {
                WelcomeView()
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
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .background: model.didEnterBackground()
            case .active: model.didBecomeActive()
            default: break
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            model.restoreFromKeychain()
            while !Task.isCancelled {
                await model.larder?.sync()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
