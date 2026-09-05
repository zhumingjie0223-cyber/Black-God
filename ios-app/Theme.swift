//
//  Theme.swift — 玄黑森林·翡翠活光主题 · 统一设计令牌
//

import SwiftUI

extension Color {
    static let bgGold = Color(red: 0.25, green: 0.48, blue: 0.35)
    static let bgGoldLight = Color(red: 0.31, green: 0.78, blue: 0.48)
    static let bgDark = Color(red: 0.043, green: 0.082, blue: 0.055)
    static let bgCard = Color(red: 0.078, green: 0.129, blue: 0.098)
    static let bgCardLight = Color(red: 0.118, green: 0.188, blue: 0.141)
    static let bgPurple = Color(red: 0.38, green: 0.30, blue: 0.48)
    static let bgCyan = Color(red: 0.42, green: 0.69, blue: 0.64)
    static let bgTextPrimary = Color(red: 0.91, green: 0.96, blue: 0.92)
    static let bgTextSecondary = Color(red: 0.61, green: 0.70, blue: 0.64)
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
