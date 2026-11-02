import SwiftUI

/// A placeholder until the main screen.
struct SignedInView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAccount = false

    var body: some View {
        Text("Signed in as \(model.memberName)")
            .multilineTextAlignment(.center)
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAccount = true } label: {
                        Text(verbatim: model.memberName.prefix(1).uppercased())
                            .font(.headline)
                            .foregroundStyle(Color(.systemBackground))
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Color.accentColor, in: Circle())
                    }
                    .accessibilityLabel("My account")
                    .accessibilityIdentifier("signedIn.account")
                }
            }
            .sheet(isPresented: $showingAccount) { AccountView() }
    }
}
