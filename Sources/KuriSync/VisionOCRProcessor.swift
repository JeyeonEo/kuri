#if canImport(Vision)
import Foundation
import Vision
import KuriCore

public struct VisionOCRProcessor: OCRProcessor, Sendable {
    private let maxDimension: CGFloat
    private let maxCharacters: Int

    public init(maxDimension: CGFloat = 2048, maxCharacters: Int = 10_000) {
        self.maxDimension = maxDimension
        self.maxCharacters = maxCharacters
    }

    public func processImage(at path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
        guard let imageSource,
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw OCRError.invalidImage
        }

        let resized = downscale(cgImage)
        let text = try await recognizeText(in: resized)
        return normalize(text)
    }

    private func downscale(_ image: CGImage) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let longest = max(width, height)
        guard longest > maxDimension else { return image }

        let scale = maxDimension / longest
        let newWidth = Int(width * scale)
        let newHeight = Int(height * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }

    private func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            nonisolated(unsafe) var resumed = false
            let request = VNRecognizeTextRequest { request, error in
                guard !resumed else { return }
                resumed = true
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                guard !resumed else { return }
                resumed = true
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    private func normalize(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\\s*\\n\\s*\\n\\s*", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if result.count > maxCharacters {
            let index = result.index(result.startIndex, offsetBy: maxCharacters)
            result = String(result[..<index]) + "…"
        }
        return result
    }
}

enum OCRError: Error, LocalizedError {
    case invalidImage
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not load image for OCR."
        case .recognitionFailed(let message):
            return "OCR failed: \(message)"
        }
    }
}
#endif
