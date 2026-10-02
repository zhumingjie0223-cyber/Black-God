import XCTest
@testable import BlackGod

final class NexusSandboxDemoTests: XCTestCase {
    func testShowcaseHTMLIsBrandFirstAndScriptFree() {
        let html = NexusSandboxDemo.html(kernelLine: "Linux blackgod 1.0", generatedAt: "2026-10-02T00:00:00Z")
        XCTAssertTrue(html.contains("BLACK GOD"))
        XCTAssertTrue(html.contains("沙箱已"))
        XCTAssertTrue(html.contains("Linux blackgod 1.0"))
        XCTAssertTrue(html.contains("#4FE096"))
        XCTAssertFalse(html.lowercased().contains("<script"))
        let escaped = NexusSandboxDemo.html(kernelLine: "<b>x</b>&", generatedAt: "t")
        XCTAssertTrue(escaped.contains("&lt;b&gt;x&lt;/b&gt;&amp;"))
    }
}
