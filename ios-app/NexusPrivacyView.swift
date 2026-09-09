import SwiftUI

struct NexusPrivacyView: View {
    var resource = "PRIVACY_POLICY"
    var title = "隐私与数据使用"
    @Environment(\.dismiss) private var dismiss
    private var policy: String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "说明文档暂不可用。请联系应用支持。" }
        return text
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(policy.components(separatedBy: "\n\n").enumerated()), id: \.offset) { index, paragraph in
                        Text(paragraph).font(.body).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("document.paragraph.\(index)")
                    }
                }.padding()
            }
                .navigationTitle(title)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
