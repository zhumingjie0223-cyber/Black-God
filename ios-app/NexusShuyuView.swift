import SwiftUI

struct NexusShuyuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var seed = "神枢"
    @State private var word: [String: String] = [:]
    @State private var verified = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Black God自己的枢语") {
                    Text("枢语引擎已内置，神枢可以查询词汇、编解码，并用枢语执行工具任务。这里可以检查同一个词的编号、汉译与词形是否对应。")
                    TextField("造词种子", text: $seed).accessibilityIdentifier("shuyu.seed")
                    Button("生成并核对枢语词") { generate() }.accessibilityIdentifier("shuyu.generate")
                    Text("相同种子生成相同词，用于稳定寻址；它不是把种子文字翻译成枢语。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !word.isEmpty {
                    Section("实际引擎结果") {
                        Text(word["汉"] ?? "").font(.title2).accessibilityIdentifier("shuyu.word")
                        LabeledContent("词形", value: word["词"] ?? "")
                        LabeledContent("编号", value: word["id"] ?? "")
                        Text(word["义"] ?? "").font(.subheadline)
                        Label(verified ? "词形与汉译反查一致" : "反查未通过", systemImage: verified ? "checkmark.circle" : "exclamationmark.circle")
                            .accessibilityIdentifier("shuyu.verified")
                    }.textSelection(.enabled)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Text("原词根和编号保持兼容。执行语句由神枢在内部生成并调用工具，日常使用无需学习代码。枢语的组合词汇空间不等于已训练的智能能力。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Color.bgCyan)
            .navigationTitle("枢语")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
    private func generate() {
        do {
            let value = try NexusShuyuEngine.shared.invoke("造词", input: seed)
            guard let object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
                  let id = object["id"] as? NSNumber, let han = object["汉"] as? String, let form = object["词"] as? String else { throw NexusError.invalidResponse }
            word = ["id": id.stringValue, "汉": han, "词": form, "义": object["义"] as? String ?? ""]
            let latinID = try NexusShuyuEngine.shared.invoke("拉丁编号", input: form)
            let hanID = try NexusShuyuEngine.shared.invoke("汉译编号", input: han)
            verified = latinID == id.stringValue && hanID == id.stringValue
            error = nil
        } catch { word = [:]; verified = false; self.error = error.localizedDescription }
    }
}
