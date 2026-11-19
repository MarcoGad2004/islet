import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
    // docs/DESIGN.md "Visual tokens"
    static let isletText = Color(hex: 0xF5F5F7)
    static let isletSecondary = Color(hex: 0xA1A1A6)
    static let isletTertiary = Color(hex: 0x8E8E93)
    static let isletGreen = Color(hex: 0x32D74B)
    static let isletCyan = Color(hex: 0x64D2FF)
    static let isletRed = Color(hex: 0xFF453A)
    static let isletRing = Color(hex: 0x2C2C2E)
}
