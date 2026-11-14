import SwiftUI

/// How to make this iPhone trust a server's own root certificate. Text only, opened from Enter invite.
struct CertificateHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("This iPhone only connects to servers it trusts. To trust a server with its own certificate, install its root certificate:")
                step(1, "Get the root certificate from the server's admin and open it on this iPhone.")
                step(2, "In Settings › General › VPN & Device Management, install it.")
                step(3, "In Settings › General › About › Certificate Trust Settings, turn it on.")
                Text("This iPhone then trusts the certificate for every website. Anyone with its key could pose as any website. Only do this for testing.")
                    .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("certificateHelp")
        .navigationTitle("Servers with their own certificate")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A hanging number, read with its step as one.
    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(number).").monospacedDigit()
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}
