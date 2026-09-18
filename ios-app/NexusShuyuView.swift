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
                    Button("用「奥形凝起」做恒等类比") { analogize() }.accessibilityIdentifier("shuyu.analogy")
                    Button("查看「奥形凝起」的邻近词") { neighbors() }.accessibilityIdentifier("shuyu.near")
                    Button("看「奥形凝起」此刻一息") { pulse() }.accessibilityIdentifier("shuyu.pulse")
                    Button("看「奥形凝起」余息三格") { trail() }.accessibilityIdentifier("shuyu.trail")
                    Button("看「奥形凝起」回息弹回") { echo() }.accessibilityIdentifier("shuyu.echo")
                    Button("看「奥形凝起」摇息摇摆") { sway() }.accessibilityIdentifier("shuyu.sway")
                    Button("看「奥形凝起」落息落地") { land() }.accessibilityIdentifier("shuyu.land")
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
            .tint(Color.bgJadeHi)
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
    private func analogize() {
        do {
            let value = try NexusShuyuEngine.shared.invoke("类比", input: #"["奥形凝起","奥形凝起","奥形凝起"]"#)
            guard let object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
                  let id = object["id"] as? NSNumber, let han = object["汉"] as? String, let form = object["词"] as? String else { throw NexusError.invalidResponse }
            word = ["id": id.stringValue, "汉": han, "词": form, "义": object["义"] as? String ?? ""]
            verified = id.intValue == 0 && han == "奥形凝起"
            error = nil
        } catch { word = [:]; verified = false; self.error = error.localizedDescription }
    }
    private func neighbors() {
        do {
            let value = try NexusShuyuEngine.shared.invoke("邻近", input: "奥形凝起")
            guard let items = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [[String: Any]],
                  let first = items.first, let id = first["id"] as? NSNumber, let han = first["汉"] as? String, let form = first["词"] as? String else { throw NexusError.invalidResponse }
            let names = items.compactMap { $0["汉"] as? String }.joined(separator: "、")
            word = ["id": id.stringValue, "汉": han, "词": form, "义": "邻近 \(items.count) 个：\(names)"]
            verified = items.count == 5 && !(items.contains { ($0["id"] as? NSNumber)?.intValue == 0 })
            error = nil
        } catch { word = [:]; verified = false; self.error = error.localizedDescription }
    }
    private func pulse() {
        do {
            let at = String(Int(Date().timeIntervalSince1970))
            let value = try NexusShuyuEngine.shared.invoke("一息", input: #"["奥形凝起","\#(at)"]"#)
            guard let object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
                  let id = object["id"] as? NSNumber, let han = object["汉"] as? String, let form = object["词"] as? String,
                  let phase = object["息"] as? String else { throw NexusError.invalidResponse }
            word = ["id": id.stringValue, "汉": han, "词": form, "义": "一息 \(phase)"]
            verified = ["晨", "昼", "昏", "夜"].contains(phase)
            error = nil
        } catch { word = [:]; verified = false; self.error = error.localizedDescription }
    }
    private func trail() {
        do {
            let at = String(Int(Date().timeIntervalSince1970))
            let value = try NexusShuyuEngine.shared.invoke("余息", input: #"["奥形凝起","\#(at)",3]"#)
            guard let object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
                  let id = object["id"] as? NSNumber, let han = object["汉"] as? String, let form = object["词"] as? String,
                  let steps = object["迹"] as? [Any], let count = object["步"] as? NSNumber else { throw NexusError.invalidResponse }
            let names = steps.compactMap { ($0 as? [String: Any])?["汉"] as? String }.joined(separator: " → ")
            word = ["id": id.stringValue, "汉": han, "词": form, "义": "余息 \(count.intValue) 格：\(names)"]
            verified = count.intValue == steps.count && (2...4).contains(count.intValue)
            error = nil
        } catch { word = [:]; verified = false; self.error = error.localizedDescription }
    }
    private func echo() {
        do {
            let at = String(Int(Date().timeIntervalSince1970))
            let value = try NexusShuyuEngine.shared.invoke("回息", input: #"["奥形凝起","\#(at)",3]"#)
            guard let object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
                  let id = object["id"] as? NSNumber, let han = object["汉"] as? String, let form = object["词"] as? String,
                  let steps = object["迹"] as? [Any], let count = object["步"] as? NSNumber else { throw NexusError.invalidResponse }
            let names = steps.compactMap { ($0 as? [String: Any])?["汉"] as? String }.joined(separator: " → ")
            let bounced = (object["回"] as? NSNumber)?.boolValue ?? (object["回"] as? Bool ?? false)
            word = ["id": id.stringValue, "汉": han, "词": form, "义": "回息 \(count.intValue) 格\(bounced ? "弹回" : "")：\(names) ↩ \(han)"]
            verified = bounced && count.intValue == steps.count
            error = nil
        } catch { word = [:]; verified = false; self.error = error.localizedDescription }
    }
    private func sway() {
        do {
            let at = String(Int(Date().timeIntervalSince1970))
            let value = try NexusShuyuEngine.shared.invoke("摇息", input: #"["奥形凝起","\#(at)",3]"#)
            guard let object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
                  let id = object["id"] as? NSNumber, let han = object["汉"] as? String, let form = object["词"] as? String,
                  let steps = object["迹"] as? [Any], let count = object["步"] as? NSNumber else { throw NexusError.invalidResponse }
            let names = steps.compactMap { ($0 as? [String: Any])?["汉"] as? String }.joined(separator: " → ")
            let swaying = (object["摇"] as? NSNumber)?.boolValue ?? (object["摇"] as? Bool ?? false)
            word = ["id": id.stringValue, "汉": han, "词": form, "义": "摇息 \(count.intValue) 格\(swaying ? "摇摆" : "")：\(names) ⇌ \(han)"]
            verified = swaying && count.intValue == steps.count
            error = nil
        } catch { word = [:]; verified = false; self.error = error.localizedDescription }
    }
    private func land() {
        do {
            let at = String(Int(Date().timeIntervalSince1970))
            let value = try NexusShuyuEngine.shared.invoke("落息", input: #"["奥形凝起","\#(at)",3]"#)
            guard let object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
                  let id = object["id"] as? NSNumber, let han = object["汉"] as? String, let form = object["词"] as? String,
                  let steps = object["迹"] as? [Any], let count = object["步"] as? NSNumber else { throw NexusError.invalidResponse }
            let names = steps.compactMap { ($0 as? [String: Any])?["汉"] as? String }.joined(separator: " → ")
            let landed = (object["落"] as? NSNumber)?.boolValue ?? (object["落"] as? Bool ?? false)
            let ground = (object["着"] as? [String: Any])?["汉"] as? String ?? han
            word = ["id": id.stringValue, "汉": han, "词": form, "义": "落息 \(count.intValue) 格\(landed ? "落地" : "未落")：\(names) ⤵ \(ground)"]
            verified = count.intValue == steps.count
            error = nil
        } catch { word = [:]; verified = false; self.error = error.localizedDescription }
    }
}
