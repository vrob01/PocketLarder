import PocketLarderKit
import SwiftUI
import UIKit

extension Color {
    /// One light and one dark color per token. Each reaches 4.5:1 on its own 15% tint, which is how tags use it.
    init(_ token: ListColor) {
        self.init(uiColor: dynamicColor(token))
    }
}

extension Image {
    /// A menu draws a plain image in one color, so the dot has to carry its own.
    init(dot token: ListColor) {
        self.init(uiImage: UIImage(systemName: "circle.fill")!.withTintColor(dynamicColor(token), renderingMode: .alwaysOriginal))
    }
}

private func dynamicColor(_ token: ListColor) -> UIColor {
    UIColor { traits in
        let (light, dark) = rgb(token)
        let value = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
            red: CGFloat(value >> 16 & 0xFF) / 255,
            green: CGFloat(value >> 8 & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

private func rgb(_ token: ListColor) -> (light: UInt32, dark: UInt32) {
    switch token {
    case .red: (0xB3261E, 0xFF8A80)
    case .orange: (0x904A00, 0xFFB366)
    case .yellow: (0x6E5500, 0xF2D05E)
    case .green: (0x256B2A, 0x81C784)
    case .teal: (0x086657, 0x3FD1B8)
    case .blue: (0x0955BA, 0x8AB8FF)
    case .purple: (0x7236B8, 0xC9A6FF)
    case .pink: (0xA81552, 0xF48FB1)
    case .gray: (0x5C6066, 0xBDC1C6)
    }
}
