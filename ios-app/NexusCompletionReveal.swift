import SwiftUI

/// 任务完成卷帘揭晓：不是弹个 Toast，而是整页级抽拉仪式。
struct NexusCompletionReveal: View {
    enum Outcome: Equatable {
        case success
        case warning
        case failure

        var title: String {
            switch self {
            case .success: return "已完成"
            case .warning: return "有告警"
            case .failure: return "失败"
            }
        }

        var symbol: String {
            switch self {
            case .success: return "checkmark.seal.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failure: return "xmark.octagon.fill"
            }
        }

        var accent: Color {
            switch self {
            case .success: return .bgJadeHi
            case .warning, .failure: return .orange
            }
        }
    }

    let outcome: Outcome
    let goal: String
    let detail: String
    var onOpenTheater: () -> Void
    var onDismiss: () -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: CGFloat = 0
    @State private var glow = false
    @State private var dragY: CGFloat = 0

    private let spring = Animation.spring(response: 0.52, dampingFraction: 0.82)

    var body: some View {
        ZStack {
            Color.black.opacity(0.55 + 0.2 * Double(reveal))
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                panel
                    .offset(y: (1 - reveal) * 120 + dragY)
                    .opacity(Double(reveal))
            }
        }
        .accessibilityIdentifier("completion.reveal")
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : spring) {
                reveal = 1
                glow = true
            }
            appState.taskCompleteHaptic(success: outcome == .success)
            // 卷帘卡点轻触
            if appState.hapticEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    appState.haptic(.soft)
                }
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(outcome.accent.opacity(0.55))
                .frame(width: 46, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 10)

            shutterRail

            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(outcome.accent.opacity(glow ? 0.28 : 0.12))
                        .frame(width: 64, height: 64)
                        .blur(radius: glow && !reduceMotion ? 10 : 0)
                    Image(systemName: outcome.symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(outcome.accent)
                        .scaleEffect(reveal > 0.5 ? 1 : 0.72)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(outcome.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.bgTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("completion.title")
                    Text(goal.isEmpty ? "本次任务" : goal)
                        .font(.subheadline)
                        .foregroundStyle(Color.bgTextSecondary)
                        .lineLimit(3)
                        .accessibilityIdentifier("completion.goal")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.bgTextPrimary.opacity(0.9))
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .lineLimit(4)
                .accessibilityIdentifier("completion.detail")

            HStack(spacing: 10) {
                Button(action: {
                    appState.haptic(.light)
                    onOpenTheater()
                    dismiss()
                }) {
                    Label("过程", systemImage: "rectangle.bottomhalf.inset.filled")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(BGPrimaryButtonStyle())
                .accessibilityIdentifier("completion.openTheater")
                .accessibilityLabel("查看过程")

                Button(action: dismiss) {
                    Text("好")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(BGSecondaryButtonStyle())
                .accessibilityIdentifier("completion.dismiss")
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Color.bgCard.opacity(0.97)
                LinearGradient(
                    colors: [outcome.accent.opacity(0.18), .clear, Color.bgJade.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .background(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(outcome.accent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: outcome.accent.opacity(0.22), radius: 36, y: -8)
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard !reduceMotion else { return }
                    dragY = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > 110 || value.predictedEndTranslation.height > 200 {
                        dismiss()
                    } else {
                        withAnimation(spring) { dragY = 0 }
                    }
                }
        )
    }

    private var shutterRail: some View {
        HStack(spacing: 3) {
            ForEach(0..<14, id: \.self) { i in
                Capsule()
                    .fill(outcome.accent.opacity(0.12 + Double((i + Int(reveal * 10)) % 4) * 0.06))
                    .frame(height: 3)
                    .scaleEffect(x: 1, y: glow && !reduceMotion ? 1.35 : 1)
            }
        }
        .padding(.horizontal, 22)
        .accessibilityHidden(true)
    }

    private func dismiss() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : spring) {
            reveal = 0
            dragY = 80
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.16 : 0.28)) {
            onDismiss()
        }
    }
}

extension NexusCompletionReveal.Outcome {
    static func from(_ state: NexusLiveExecution.State) -> Self? {
        switch state {
        case .answered: return .success
        case .warning: return .warning
        case .failed: return .failure
        default: return nil
        }
    }
}
