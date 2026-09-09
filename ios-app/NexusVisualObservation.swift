import Foundation
import Vision
import ImageIO
import CryptoKit

enum NexusVisualObservation {
    struct Result { let text: String; let source: String; let minimumConfidence: Float }
    static func recognize(_ data: Data) throws -> Result {
        guard !data.isEmpty, data.count <= 20_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw NexusReasoningError.execution("图片无效或超过20MB") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = (request.results ?? []).compactMap { $0.topCandidates(1).first }
        guard !observations.isEmpty else { throw NexusReasoningError.execution("没有识别到文字；不能据此判断图片内容不存在。") }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Result(text: String(observations.map(\.string).joined(separator: "\n").prefix(6000)),
                      source: "用户选择图片的本机OCR；SHA256=" + hash + "；" + Date().ISO8601Format(),
                      minimumConfidence: observations.map(\.confidence).min() ?? 0)
    }
}
