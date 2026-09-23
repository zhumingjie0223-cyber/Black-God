// Black God — restrained forest surfaces, jade actions, shared UI components.
import SwiftUI

extension Color {
    static let bgJade = Color(red: 0.25, green: 0.48, blue: 0.35)
    static let bgJadeHi = Color(red: 0.31, green: 0.78, blue: 0.48)
    // Compatibility names used by older screens.
    static let bgGold = bgJade
    static let bgGoldLight = bgJadeHi
    static let bgDark = Color(red: 0.043, green: 0.082, blue: 0.055)
    static let bgCard = Color(red: 0.072, green: 0.105, blue: 0.086)
    static let bgCardLight = Color(red: 0.112, green: 0.161, blue: 0.133)
    static let bgPurple = Color(red: 0.63, green: 0.62, blue: 0.79)
    static let bgCyan = Color(red: 0.50, green: 0.77, blue: 0.72)
    static let bgTextPrimary = Color(red: 0.93, green: 0.96, blue: 0.94)
    static let bgTextSecondary = Color(red: 0.63, green: 0.72, blue: 0.67)
    static let bgBorder = Color.white.opacity(0.08)
}

extension LinearGradient {
    static let goldGradient = LinearGradient(colors: [.bgJade, .bgJadeHi], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let darkGradient = LinearGradient(colors: [Color(red: 0.047, green: 0.067, blue: 0.055), .bgDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cyberGradient = LinearGradient(colors: [.bgJadeHi, .bgCyan], startPoint: .leading, endPoint: .trailing)
}

extension Font {
    static func bgTitle() -> Font { .system(.largeTitle, design: .rounded).weight(.semibold) }
    static func bgHeadline() -> Font { .system(.headline, design: .rounded) }
    static func bgBody() -> Font { .system(.body) }
    static func bgCaption() -> Font { .system(.subheadline) }
}

struct BGCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(18)
            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.bgBorder, lineWidth: 1))
    }
}
extension View {
    func bgCard() -> some View { modifier(BGCardModifier()) }
}

struct BGPageHeader: View {
    let title: String
    let subtitle: String
    var eyebrow: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Text(eyebrow).font(.caption2.weight(.bold)).tracking(2).foregroundStyle(Color.bgJadeHi)
            }
            Text(title).font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).foregroundStyle(Color.bgTextSecondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }
}

struct BGPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(enabled ? Color.bgDark : Color.bgTextSecondary)
            .background(enabled ? Color.bgJadeHi : Color.bgCardLight, in: RoundedRectangle(cornerRadius: 15))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct BGSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
            .foregroundStyle(enabled ? Color.bgJadeHi : Color.bgTextSecondary)
            .background(Color.bgCardLight, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.bgBorder, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.55)
    }
}

/// Floating surfaces share the original jade palette; callers own their spacing.
private struct BGFloatingModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(Color.bgCard.opacity(reduceTransparency ? 1 : 0.86), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(LinearGradient(colors: [Color.bgJadeHi.opacity(0.30), Color.white.opacity(0.06), Color.bgJade.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(0.26), radius: 18, x: 0, y: 10)
            .shadow(color: .bgJadeHi.opacity(0.045), radius: 18)
    }
}

extension View {
    func bgFloating(cornerRadius: CGFloat = 24) -> some View { modifier(BGFloatingModifier(radius: cornerRadius)) }
}

/// Decorative light, never a progress indicator. Motion pauses outside the active app.
struct BGAuraOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var epoch = Date()
    var diameter: CGFloat = 240

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || scenePhase != .active)) { timeline in
            BGAuraFrame(diameter: diameter, time: reduceMotion ? 0 : timeline.date.timeIntervalSince(epoch))
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct BGAuraFrame: View {
    let diameter: CGFloat
    let time: TimeInterval

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.bgJadeHi.opacity(0.22), Color.bgJade.opacity(0.08), .clear], center: .center, startRadius: 0, endRadius: diameter * 0.5))
                .scaleEffect(1.08 + sin(time * 0.9) * 0.06)
            Circle().stroke(Color.bgJadeHi.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [2, 9]))
                .padding(diameter * 0.035)
            Circle().trim(from: 0.03, to: 0.29)
                .stroke(LinearGradient(colors: [.clear, Color.bgJadeHi.opacity(0.8)], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .padding(diameter * 0.07).rotationEffect(.radians(time * 0.2))
                .shadow(color: Color.bgJadeHi.opacity(0.55), radius: 7)
            orbits
            Circle()
                .fill(RadialGradient(colors: [Color.bgJadeHi.opacity(0.35), Color.bgJade.opacity(0.22), Color.bgDark.opacity(0.15)], center: .topLeading, startRadius: 0, endRadius: diameter * 0.45))
                .frame(width: diameter * 0.44, height: diameter * 0.44)
                .overlay(Circle().stroke(Color.bgJadeHi.opacity(0.36), lineWidth: 0.8))
                .shadow(color: Color.bgJadeHi.opacity(0.24), radius: 24)
            Image(systemName: "sparkle")
                .font(.system(size: diameter * 0.19, weight: .ultraLight))
                .foregroundStyle(Color.bgJadeHi)
                .shadow(color: Color.bgJadeHi.opacity(0.9), radius: 12)
                .scaleEffect(1 + sin(time * 1.1) * 0.055)
        }
        .offset(y: sin(time * 0.65) * 5)
    }

    private var orbits: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for orbit in 0..<3 {
                let tilt = Double(orbit) * .pi / 3 + time * (orbit == 1 ? -0.08 : 0.10)
                let major = size.width * 0.39
                let minor = size.height * (0.15 + Double(orbit) * 0.015)
                func point(_ angle: Double) -> CGPoint {
                    let x = cos(angle) * major, y = sin(angle) * minor
                    return CGPoint(x: center.x + x * cos(tilt) - y * sin(tilt), y: center.y + x * sin(tilt) + y * cos(tilt))
                }
                var path = Path()
                for segment in 0...96 {
                    let p = point(Double(segment) / 96 * .pi * 2)
                    if segment == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                var glow = context
                glow.addFilter(.shadow(color: Color.bgJadeHi.opacity(0.5), radius: 5))
                glow.stroke(path, with: .linearGradient(Gradient(colors: [Color.bgJade.opacity(0.10), Color.bgJadeHi.opacity(0.85), Color.bgJadeHi.opacity(0.18)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 1.1)
                let dot = point(time * (0.42 + Double(orbit) * 0.12) + Double(orbit) * 2)
                glow.fill(Path(ellipseIn: CGRect(x: dot.x - 2.4, y: dot.y - 2.4, width: 4.8, height: 4.8)), with: .color(Color.bgJadeHi))
            }
        }
    }
}
