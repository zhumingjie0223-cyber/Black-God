import SwiftUI

/// 抽拉式卷帘面板：弹簧展开、卡点触感、玉绿扫光——不是普通折叠。
struct BGPullDrawer<Content: View>: View {
    @Binding var isOpen: Bool
    var title: String
    var accessibilityID: String = "drawer"
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var sweep: CGFloat = 0

    private let spring = Animation.spring(response: 0.48, dampingFraction: 0.84)

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    shutterSlats
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(
                    reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
            }
        }
        .bgFloating(cornerRadius: 22)
        .overlay {
            if isOpen && !reduceMotion {
                LinearGradient(
                    colors: [.clear, Color.bgJadeHi.opacity(0.18), .clear],
                    startPoint: UnitPoint(x: sweep - 0.2, y: 0),
                    endPoint: UnitPoint(x: sweep + 0.2, y: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .allowsHitTesting(false)
            }
        }
        .offset(y: reduceMotion ? 0 : dragOffset)
        .simultaneousGesture(drag)
        .animation(reduceMotion ? .easeInOut(duration: 0.16) : spring, value: isOpen)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID)
        .onChange(of: isOpen) { _, open in
            appState.haptic(open ? .medium : .soft)
            guard open, !reduceMotion else { return }
            sweep = 0
            withAnimation(.easeInOut(duration: 0.7)) { sweep = 1 }
        }
    }

    private var handle: some View {
        Capsule()
            .fill(Color.bgJadeHi.opacity(0.55))
            .frame(width: 40, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { toggle() }
            .accessibilityHidden(true)
    }

    private var header: some View {
        Button(action: toggle) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.bgTextPrimary)
                Spacer()
                Image(systemName: "chevron.compact.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.bgJadeHi)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(accessibilityID).toggle")
        .accessibilityLabel(isOpen ? "收起\(title)" : "展开\(title)")
    }

    private var shutterSlats: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(Color.bgJadeHi.opacity(0.16 + Double(i % 3) * 0.07))
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !reduceMotion else { return }
                if isOpen {
                    dragOffset = min(0, max(-40, value.translation.height * 0.35))
                } else {
                    dragOffset = max(0, min(40, value.translation.height * 0.35))
                }
            }
            .onEnded { value in
                let dy = value.translation.height
                let predicted = value.predictedEndTranslation.height
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : spring) {
                    if isOpen, dy < -28 || predicted < -80 {
                        isOpen = false
                    } else if !isOpen, dy > 28 || predicted > 80 {
                        isOpen = true
                    }
                    dragOffset = 0
                }
            }
    }

    private func toggle() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : spring) {
            isOpen.toggle()
            dragOffset = 0
        }
    }
}

/// 从底部抽拉的执行剧场覆盖层。
struct BGBottomDrawer<Content: View>: View {
    @Binding var isPresented: Bool
    var title: String
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var sweep: CGFloat = 0

    private let spring = Animation.spring(response: 0.48, dampingFraction: 0.86)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(isPresented ? 0.52 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .accessibilityHidden(!isPresented)

                if isPresented {
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Color.bgJadeHi.opacity(0.55))
                            .frame(width: 44, height: 5)
                            .padding(.top, 10)
                            .padding(.bottom, 8)
                        HStack {
                            Text(title).font(.headline).foregroundStyle(Color.bgTextPrimary)
                            Spacer()
                            Button("好") { dismiss() }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.bgJadeHi)
                                .accessibilityIdentifier("drawer.dismiss")
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                        HStack(spacing: 3) {
                            ForEach(0..<12, id: \.self) { i in
                                Capsule()
                                    .fill(Color.bgJadeHi.opacity(0.18 + Double(i % 3) * 0.08))
                                    .frame(height: 3)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .accessibilityHidden(true)

                        ScrollView {
                            content()
                                .padding(.horizontal, 20)
                                .padding(.bottom, 28)
                        }
                        .frame(maxHeight: geo.size.height * 0.72)
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        Color.bgCard
                            .opacity(0.96)
                            .background(.ultraThinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.bgJadeHi.opacity(0.28), lineWidth: 1)
                    )
                    .overlay {
                        if !reduceMotion {
                            LinearGradient(
                                colors: [.clear, Color.bgJadeHi.opacity(0.14), .clear],
                                startPoint: UnitPoint(x: sweep - 0.15, y: 0),
                                endPoint: UnitPoint(x: sweep + 0.15, y: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .allowsHitTesting(false)
                        }
                    }
                    .shadow(color: Color.bgJadeHi.opacity(0.16), radius: 28, y: -6)
                    .offset(y: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !reduceMotion else { return }
                                dragOffset = max(0, value.translation.height)
                            }
                            .onEnded { value in
                                if value.translation.height > 120 || value.predictedEndTranslation.height > 220 {
                                    dismiss()
                                } else {
                                    withAnimation(spring) { dragOffset = 0 }
                                    appState.haptic(.soft)
                                }
                            }
                    )
                    .transition(
                        reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .accessibilityIdentifier("bottom.drawer")
                    .onAppear {
                        appState.haptic(.medium)
                        guard !reduceMotion else { return }
                        sweep = 0
                        withAnimation(.easeInOut(duration: 0.75)) { sweep = 1 }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(isPresented)
        .animation(reduceMotion ? .easeInOut(duration: 0.18) : spring, value: isPresented)
        .onChange(of: isPresented) { _, presented in
            if !presented { dragOffset = 0 }
        }
    }

    private func dismiss() {
        appState.haptic(.soft)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : spring) {
            isPresented = false
            dragOffset = 0
        }
    }
}
