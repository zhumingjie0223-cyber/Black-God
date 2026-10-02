import SwiftUI

/// 抽拉式卷帘面板：把手下拉展开 / 上推收起；内容整块弹簧卷开，不裁掉可点控件。
struct BGPullDrawer<Content: View>: View {
    @Binding var isOpen: Bool
    var title: String
    var accessibilityID: String = "drawer"
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

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
        .offset(y: reduceMotion ? 0 : dragOffset)
        .simultaneousGesture(drag)
        .animation(reduceMotion ? .easeInOut(duration: 0.16) : spring, value: isOpen)
        .accessibilityElement(children: .contain)
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

/// 从底部抽拉的覆盖层，用于任务详情一类面板。
struct BGBottomDrawer<Content: View>: View {
    @Binding var isPresented: Bool
    var title: String
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

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
                    .shadow(color: Color.bgJadeHi.opacity(0.14), radius: 28, y: -6)
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
                                }
                            }
                    )
                    .transition(
                        reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .accessibilityIdentifier("bottom.drawer")
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
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : spring) {
            isPresented = false
            dragOffset = 0
        }
    }
}
