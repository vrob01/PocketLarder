import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var signingOut = false
    @State private var question: String?

    var body: some View {
        NavigationStack {
            List {
                Button(role: .destructive) {
                    signOut(force: false)
                } label: {
                    HStack {
                        Text("Sign out")
                        if signingOut {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(signingOut)
                .accessibilityIdentifier("account.signOut")
            }
            .navigationTitle("My account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(signingOut)
                }
            }
        }
        .interactiveDismissDisabled(signingOut)
        .alert(
            question ?? "",
            isPresented: Binding(
                get: { question != nil },
                set: { if !$0 { question = nil } }
            )
        ) {
            Button("Sign out anyway", role: .destructive) { signOut(force: true) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func signOut(force: Bool) {
        signingOut = true
        Task {
            switch await model.signOut(force: force) {
            case .done: break // The root swaps to the welcome screen.
            case let .unsentChanges(count): question = unsentChangesText(count)
            case .unreachable: question = String(localized: "Can't reach your server. Sign out anyway? This deletes everything on this iPhone. Ask an admin to remove this device from the household.")
            }
            signingOut = false
        }
    }
}

func unsentChangesText(_ count: Int) -> String {
    String(localized: "\(count) changes haven't been sent yet. Sign out and lose them?")
}
