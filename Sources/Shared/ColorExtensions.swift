import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// Creates a Color from a "#RRGGBB" or "#RRGGBBAA" hex string. Falls back to lavender.
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb), (hexSanitized.count == 6 || hexSanitized.count == 8) else {
            self = Color(red: 0.65, green: 0.55, blue: 0.98)
            return
        }

        let r, g, b, a: Double
        if hexSanitized.count == 8 {
            r = Double((rgb & 0xFF00_0000) >> 24) / 255
            g = Double((rgb & 0x00FF_0000) >> 16) / 255
            b = Double((rgb & 0x0000_FF00) >> 8) / 255
            a = Double(rgb & 0x0000_00FF) / 255
        } else {
            r = Double((rgb & 0xFF0000) >> 16) / 255
            g = Double((rgb & 0x00FF00) >> 8) / 255
            b = Double(rgb & 0x0000FF) / 255
            a = 1.0
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }

    /// Best-effort hex string, used for persistence. Not colorspace-perfect but sufficient for UI accents.
    func toHex() -> String {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return "#8B5CF6"
        #endif
    }
}

enum AccentPreset: String, CaseIterable, Identifiable {
    case lavender, purple, blue, cyan, green, orange, pink, red

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .lavender: return "#B7A6F7"
        case .purple: return "#8B5CF6"
        case .blue: return "#60A5FA"
        case .cyan: return "#22D3EE"
        case .green: return "#34D399"
        case .orange: return "#FB923C"
        case .pink: return "#F472B6"
        case .red: return "#F87171"
        }
    }

    var color: Color { Color(hex: hex) }
    var displayName: String { rawValue.capitalized }
}
