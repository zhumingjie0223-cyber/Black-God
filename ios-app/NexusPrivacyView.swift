import SwiftUI

struct NexusPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    private var policy: String {
        guard let url = Bundle.main.url(forResource: "PRIVACY_POLICY", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "隐私政策暂时无法读取。请联系支持：github.com/zhumingjie0223-cyber/Black-God/issues"
        }
        return text
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(.init(policy)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .navigationTitle("隐私政策")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
