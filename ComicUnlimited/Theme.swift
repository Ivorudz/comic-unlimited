import SwiftUI
import UIKit

// Colores de la app, copiados del prototipo web.
// Cada color tiene una versión clara y otra oscura (modo oscuro del iPhone).
enum Theme {
    static let paper = Color(light: 0xEEF2F4, dark: 0x121419)
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1F26)
    static let ink = Color(light: 0x17191E, dark: 0xEEF1F4)
    static let ink2 = Color(light: 0x5B6170, dark: 0x9AA1AE)
    static let line = Color(light: 0xD5DCE1, dark: 0x2B2F38)
    static let chip = Color(light: 0xE1E7EB, dark: 0x262A33)
    static let cyan = Color(light: 0x0090C4, dark: 0x3CC3F0)
    static let magenta = Color(light: 0xD1006C, dark: 0xFF4FA3)
    static let star = Color(light: 0xE8A800, dark: 0xFFD400)
    static let yellow = Color(hex: 0xFFD400)
}

extension Color {
    /// Crea un color a partir de un número hexadecimal, por ejemplo 0xD1006C.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Color que cambia solo entre modo claro y modo oscuro.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension View {
    /// El efecto de "impresión corrida" de los títulos del prototipo (sombra cian y magenta).
    func misprint(_ strength: CGFloat = 1) -> some View {
        self
            .shadow(color: Theme.cyan.opacity(0.55), radius: 0, x: 3 * strength, y: 1.5 * strength)
            .shadow(color: Theme.magenta.opacity(0.5), radius: 0, x: -2 * strength, y: -1 * strength)
    }
}
