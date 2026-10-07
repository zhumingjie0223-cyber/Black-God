import Foundation
import COpenSSL

// Implements only the SHA-256 API used by the selected production sources,
// using the installed OpenSSL library. No digest or verification is mocked.
public enum SHA256 {
    public static func hash(data: Data) -> [UInt8] {
        var digest = [UInt8](repeating: 0, count: 32)
        let succeeded = data.withUnsafeBytes { input in
            digest.withUnsafeMutableBufferPointer { output in
                black_god_sha256(input.bindMemory(to: UInt8.self).baseAddress, input.count, output.baseAddress)
            }
        }
        precondition(succeeded == 1, "OpenSSL SHA-256 failed")
        return digest
    }
}
