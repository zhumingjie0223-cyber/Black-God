import SwiftUI
import UIKit
import WebKit

/// 工作区文件本机可视预览：HTML 用内嵌页渲染，文本直接显示。不是远程浏览器自动化。
struct NexusWorkspacePreview: View {
    let path: String
    let data: Data
    @Environment(\.dismiss) private var dismiss

    private var isHTML: Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".html") || lower.hasSuffix(".htm") || lower.hasSuffix(".xhtml")
    }

    private var textBody: String {
        String(decoding: data, as: UTF8.self)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isHTML {
                    NexusHTMLWebView(html: textBody, baseURL: nil)
                        .accessibilityIdentifier("sandbox.preview.web")
                } else {
                    ScrollView {
                        Text(textBody)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color.bgTextPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    .background(Color.bgDark)
                    .accessibilityIdentifier("sandbox.preview.text")
                }
            }
            .navigationTitle(path)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct NexusHTMLWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(html, baseURL: baseURL)
    }
}
