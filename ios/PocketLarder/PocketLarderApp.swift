import SwiftUI

@main
struct PocketLarderApp: App {
    @State private var model: AppModel = {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "fixture") {
        case "household": return .fixture()
        case "offline": return .fixture(offline: true)
        case "outdated": return .fixture(outdated: true)
        default: break
        }
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
    /// The app's own model, which holds the demo's while it runs.
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    /// So that the activation runs again for a new model on screen, and the demo checks and syncs as soon as it starts.
    private struct Activation: Equatable {
        let phase: ScenePhase
        let model: ObjectIdentifier
    }

    var body: some View {
        // The demo's while it runs, for every screen and request under the root and everything the root does.
        let model = app.demo ?? app
        Group {
            // In place of the stack, so that every sheet and page over the main screen goes too.
            if let incompatibility = model.incompatibility, let account = model.account {
                IncompatibleView(incompatibility: incompatibility, host: account.server.host() ?? "", refresh: { await model.checkServer() }) {
                    BlockedSignOutButton()
                }
            } else {
                NavigationStack {
                    if let larder = model.larder {
                        MainView(larder: larder)
                    } else {
                        WelcomeView()
                    }
                }
                // A new stack, so that a pushed `EnterInviteView` can't survive signing in.
                .id(model.account == nil)
            }
        }
        .environment(model)
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
        .task(id: Activation(phase: scenePhase, model: ObjectIdentifier(model))) {
            guard scenePhase == .active else { return }
            model.restoreFromKeychain()
            // It syncs as soon as the server checks out, or can't be checked.
            await model.checkServer()
            // Then every minute, until the sleep ends early because the scene phase changed.
            while (try? await Task.sleep(for: .seconds(60))) != nil {
                await model.larder?.sync()
            }
        }
    }
}
