import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showingForm = false
    @State private var signedOutMessage: String?
    @ScaledMetric private var logoSize = 96.0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
                    .accessibilityHidden(true)
                Text(verbatim: "PocketLarder")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                if let signedOutMessage {
                    Text(signedOutMessage)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("welcome.signedOut")
                }
                Text("Shopping lists for your household. To start, this iPhone needs an invite from someone in your household: scan its QR code with the Camera app.")
                    .multilineTextAlignment(.center)
                Button("Enter invite") { showingForm = true }
                    .buttonStyle(AccentButtonStyle())
                    .accessibilityIdentifier("welcome.enterInvite")
                Link(destination: URL(string: "https://github.com/vrob01/PocketLarder#self-hosting")!) {
                    HStack(spacing: 4) {
                        Text("Set up your own server")
                        Image(systemName: "arrow.up.right").accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                }
                Text("Open source and private. No tracking, no ads, no analytics. Your lists are stored only on your household's own server.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showingForm) { EnterInviteView() }
        .onChange(of: model.pendingInvite, initial: true) {
            if model.pendingInvite != nil { showingForm = true }
        }
        .onChange(of: model.signedOutLostChanges, initial: true) {
            guard let lostChanges = model.signedOutLostChanges else { return }
            signedOutMessage = signedOutText(lostChanges: lostChanges)
            model.signedOutLostChanges = nil
        }
    }
}

func signedOutText(lostChanges: Int) -> String {
    let signedOut = String(localized: "This iPhone was signed out.")
    guard lostChanges > 0 else { return signedOut }
    return signedOut + String(localized: " \(lostChanges) changes that weren't sent yet are lost.")
}

/// Accent fill with the system background as label: 5:1 in light, 11:1 in dark.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color(.systemBackground))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}
