import SwiftUI

struct NexusPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    private var policy: String {
        guard let url = Bundle.main.url(forResource: "PRIVACY_POLICY", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "隐私政策暂不可用。请联系应用支持。" }
        return text
    }
    var body: some View {
        NavigationStack {
            ScrollView { Text(policy).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                .navigationTitle("隐私与数据使用")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
