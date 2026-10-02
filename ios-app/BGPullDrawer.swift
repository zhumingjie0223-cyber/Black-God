import SwiftUI

/// 抽拉式卷帘面板：把手下拉展开 / 上推收起，高度像卷帘卷开。
struct BGPullDrawer<Content: View>: View {
    @Binding var isOpen: Bool
    var title: String
    var accessibilityID: String = "drawer"
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var reveal: CGFloat = 0
    @State private var contentHeight: CGFloat = 1

    private let spring = Animation.spring(response: 0.48, dampingFraction: 0.84)

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            shutter
        }
        .bgFloating(cornerRadius: 22)
        .offset(y: reduceMotion ? 0 : dragOffset)
        .gesture(drag)
        .onAppear { reveal = isOpen ? 1 : 0 }
        .onChange(of: isOpen) { _, open in
            withAnimation(reduceMotion ? .easeInOut(duration: 0.16) : spring) {
                reveal = open ? 1 : 0
                dragOffset = 0
            }
        }
        .accessibilityIdentifier(accessibilityID)
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
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.bgTextPrimary)
            Spacer()
            Image(systemName: "chevron.compact.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.bgJadeHi)
                .rotationEffect(.degrees(reveal * 180))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("\(accessibilityID).toggle")
        .accessibilityLabel(isOpen ? "收起\(title)" : "展开\(title)")
    }

    private var shutter: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: max(0, contentHeight * reveal), alignment: .top)
            .clipped()
            .mask(shutterMask)
            .opacity(0.4 + 0.6 * Double(reveal))
            .allowsHitTesting(isOpen)
            .accessibilityHidden(!isOpen)
            .background(alignment: .top) {
                // 不受卷帘高度约束，单独量真实内容高度
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: DrawerHeightKey.self, value: geo.size.height)
                        }
                    )
            }
            .onPreferenceChange(DrawerHeightKey.self) { contentHeight = max(1, $0) }
    }

    private var shutterMask: some View {
        VStack(spacing: 1) {
            ForEach(0..<10, id: \.self) { index in
                Rectangle()
                    .fill(Color.white.opacity(slatOpacity(index)))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(8, contentHeight / 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func slatOpacity(_ index: Int) -> Double {
        guard reveal > 0 else { return 0 }
        let threshold = Double(index) / 10.0
        return min(1, max(0, (Double(reveal) - threshold) / 0.16))
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
                if isOpen, dy < -28 || predicted < -80 {
                    isOpen = false
                } else if !isOpen, dy > 28 || predicted > 80 {
                    isOpen = true
                } else {
                    withAnimation(spring) { dragOffset = 0 }
                }
            }
    }

    private func toggle() {
        isOpen.toggle()
    }
}

private struct DrawerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 从底部抽拉的覆盖层，用于任务详情一类面板（卷帘上推感）。
struct BGBottomDrawer<Content: View>: View {
    @Binding var isPresented: Bool
    var title: String
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var lift: CGFloat = 0

    private let spring = Animation.spring(response: 0.48, dampingFraction: 0.86)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(isPresented ? 0.48 : 0)
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
                            Button("完成") { dismiss() }
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
                    .shadow(color: Color.bgJadeHi.opacity(0.14), radius: 28, y: -6)
                    .offset(y: dragOffset + (1 - lift) * 48)
                    .opacity(0.55 + 0.45 * Double(lift))
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
                        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : spring) { lift = 1 }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(isPresented)
        .animation(reduceMotion ? .easeInOut(duration: 0.18) : spring, value: isPresented)
        .onChange(of: isPresented) { _, presented in
            if !presented { lift = 0; dragOffset = 0 }
        }
    }

    private func dismiss() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : spring) {
            lift = 0
            isPresented = false
            dragOffset = 0
        }
    }
}
