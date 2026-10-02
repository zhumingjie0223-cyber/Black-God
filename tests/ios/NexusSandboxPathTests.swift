import XCTest
@testable import BlackGod

final class NexusSandboxPathTests: XCTestCase {
    func testSanitizeRejectsTraversal() {
        XCTAssertEqual(NexusLinuxRuntime.sanitizeRelativePath("../etc/passwd"), "etc/passwd")
        XCTAssertEqual(NexusLinuxRuntime.sanitizeRelativePath("./a/../b"), "a/b")
        XCTAssertEqual(NexusLinuxRuntime.sanitizeFileName("/tmp/evil.txt"), "evil.txt")
        XCTAssertEqual(NexusLinuxRuntime.sanitizeFileName(""), "import.bin")
    }
}
