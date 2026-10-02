import XCTest
@testable import BlackGod

final class NexusSandboxPathTests: XCTestCase {
    func testSanitizeRejectsTraversal() {
        XCTAssertEqual(NexusWorkspacePath.sanitizeRelativePath("../etc/passwd"), "etc/passwd")
        XCTAssertEqual(NexusWorkspacePath.sanitizeRelativePath("./a/../b"), "a/b")
        XCTAssertEqual(NexusWorkspacePath.sanitizeFileName("/tmp/evil.txt"), "evil.txt")
        XCTAssertEqual(NexusWorkspacePath.sanitizeFileName(""), "import.bin")
    }
}
