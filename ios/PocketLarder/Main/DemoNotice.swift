import SwiftUI

/// While the demo runs, says that this is sample data and offers the way out. It takes its own space, so it never
/// covers an entry, a field or a button.
struct DemoNotice: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if model.isDemo {
            // Stacked at the largest sizes, so that the text keeps the whole width.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Text("You're trying PocketLarder with sample data.")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("demo.notice")
                Button {
                    model.leaveDemo()
                } label: {
                    // The system background on the accent, as on the account circle: 5:1 in light, 11:1 in dark.
                    Text("Leave")
                        .bold()
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.accentColor, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier("demo.leave")
            }
            .font(.footnote)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            // Opaque, so that rows scrolling under it on a sheet don't show through.
            .background(Color.accentColor.opacity(0.15))
            .background(.background)
        }
    }
}

extension View {
    /// The demo's notice at the bottom of a sheet, outside its stack, so that every page pushed in it shows it too.
    func demoNotice() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { DemoNotice() }
    }
}
