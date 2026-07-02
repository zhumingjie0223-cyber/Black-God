//
//  Theme.swift — 黑金暗黑主题 · 17 Pro Max适配
//

import SwiftUI

extension Color {
    static let bgGold = Color(red: 0.79, green: 0.66, blue: 0.30)
    static let bgGoldLight = Color(red: 0.92, green: 0.82, blue: 0.55)
    static let bgDark = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let bgCard = Color(red: 0.09, green: 0.09, blue: 0.12)
    static let bgCardLight = Color(red: 0.14, green: 0.14, blue: 0.18)
    static let bgPurple = Color(red: 0.55, green: 0.35, blue: 0.85)
    static let bgCyan = Color(red: 0.30, green: 0.80, blue: 0.90)
    static let bgTextPrimary = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let bgTextSecondary = Color(red: 0.60, green: 0.60, blue: 0.66)
}

extension LinearGradient {
    static let goldGradient = LinearGradient(colors: [.bgGold, .bgGoldLight], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let darkGradient = LinearGradient(colors: [Color(red: 0.06, green: 0.06, blue: 0.09), .bgDark], startPoint: .top, endPoint: .bottom)
    static let cyberGradient = LinearGradient(colors: [.bgPurple, .bgCyan], startPoint: .leading, endPoint: .trailing)
}

extension Font {
    static func bgTitle() -> Font { .system(size: 28, weight: .bold, design: .rounded) }
    static func bgHeadline() -> Font { .system(size: 18, weight: .semibold, design: .rounded) }
    static func bgBody() -> Font { .system(size: 16, weight: .regular) }
    static func bgCaption() -> Font { .system(size: 13, weight: .medium) }
}

struct BGCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.bgGold.opacity(0.15), lineWidth: 0.5)))
    }
}

extension View {
    func bgCard() -> some View { modifier(BGCardModifier()) }
}
