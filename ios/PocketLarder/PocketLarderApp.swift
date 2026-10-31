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
            NavigationStack {
                WelcomeView()
            }
            .environment(model)
            .preferredColorScheme(colorScheme)
            .onOpenURL { model.open($0) }
        }
    }
}
