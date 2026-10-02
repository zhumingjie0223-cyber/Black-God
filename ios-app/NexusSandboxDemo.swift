import Foundation

/// 沙箱一键演示：写玉绿品牌页、跑一条无害探测命令、打开本机预览。
enum NexusSandboxDemo {
    static let pagePath = "blackgod-showcase.html"
    static let probeCommand = "uname -a; date -u +%Y-%m-%dT%H:%M:%SZ; printf '\\nworkspace-ok\\n'"

    static func html(kernelLine: String, generatedAt: String) -> String {
        let safeKernel = escape(kernelLine)
        let safeTime = escape(generatedAt)
        return """
        <!doctype html>
        <html lang="zh-Hans">
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>Black God · 沙箱</title>
        <style>
          :root {
            --bg:#0B1510; --card:#121A16; --jade:#4FE096; --jade2:#3BC77E; --silver:#EAF5EE; --mute:#8FA396;
          }
          * { box-sizing: border-box; }
          html, body { margin:0; min-height:100%; background:
            radial-gradient(120% 80% at 80% -10%, rgba(79,224,150,.22), transparent 55%),
            radial-gradient(90% 60% at 10% 110%, rgba(59,199,126,.12), transparent 50%),
            var(--bg); color:var(--silver);
            font-family: "SF Pro Rounded", "PingFang SC", "Helvetica Neue", sans-serif; }
          main { min-height:100vh; display:flex; flex-direction:column; justify-content:center; padding:48px 28px 64px; }
          .eyebrow { letter-spacing:.28em; text-transform:uppercase; color:var(--jade); font-size:12px; font-weight:700; margin:0 0 18px; }
          h1 { margin:0; font-size:clamp(40px,10vw,72px); font-weight:650; line-height:1.05; letter-spacing:.02em; }
          h1 span { color:var(--jade); }
          .lead { margin:18px 0 0; max-width:28em; color:var(--mute); font-size:17px; line-height:1.6; }
          .panel { margin-top:36px; padding:18px 18px 16px; border-radius:18px; background:rgba(18,26,22,.82);
            border:1px solid rgba(79,224,150,.28); box-shadow:0 18px 50px rgba(0,0,0,.35), 0 0 40px rgba(79,224,150,.08); }
          .panel label { display:block; font-size:11px; letter-spacing:.18em; color:var(--jade2); margin-bottom:10px; }
          pre { margin:0; white-space:pre-wrap; word-break:break-word; font:13px/1.55 ui-monospace, SFMono-Regular, Menlo, monospace; color:var(--silver); }
          .footer { margin-top:28px; color:var(--mute); font-size:12px; }
        </style>
        </head>
        <body>
          <main>
            <p class="eyebrow">BLACK GOD</p>
            <h1>沙箱已<span>点亮</span></h1>
            <p class="lead">本机 Alpine Linux 工作区真实跑通：硬配额隔离、脚本审计、玉绿预览。这不是幻灯片，是你手机里的执行现场。</p>
            <section class="panel">
              <label>KERNEL PROBE</label>
              <pre>\(safeKernel)</pre>
            </section>
            <p class="footer">生成于 \(safeTime) · 预览禁脚本 · 宿主密钥未挂载</p>
          </main>
        </body>
        </html>
        """
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    @MainActor
    static func run(workspace: UUID, onPhase: @escaping (String) -> Void) async throws -> (path: String, data: Data, probe: String) {
        onPhase("正在点亮内核…")
        let result = try await NexusLinuxRuntime.shared.execute(
            command: probeCommand,
            timeout: 45,
            workspace: workspace,
            onStatus: onPhase
        )
        guard result.succeeded else {
            throw NexusReasoningError.execution(result.failure ?? result.errorOutput.ifEmpty("探测命令未成功"))
        }
        onPhase("正在写入玉绿展示页…")
        let probe = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let page = html(kernelLine: probe.isEmpty ? "(无输出)" : probe, generatedAt: stamp)
        guard let data = page.data(using: .utf8) else {
            throw NexusReasoningError.execution("展示页编码失败。")
        }
        try await NexusLinuxRuntime.shared.importToWorkspace(data: data, named: pagePath, workspace: workspace)
        onPhase("展示页已就绪")
        return (pagePath, data, probe)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
