import Foundation
import XCTest
import CryptoKit

final class PortableCryptoTests: XCTestCase {
    func testSHA256UsesKnownPublishedTestVectors() {
        for (text, expected) in [
            ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        ] {
            let actual = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(actual, expected)
        }
    }
}
