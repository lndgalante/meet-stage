import CoreGraphics
import Foundation
import Vision

/// Recognizes on-screen text in a captured frame as a fallback element source
/// for apps whose Accessibility tree is sparse (canvas or web-rendered UIs).
///
/// Results are expressed in the same `DemoElement` contract as the accessibility
/// index: normalized bounds for drawing and a global screen frame for clicking.
enum DemoTextRecognizer {
    static let maximumLabelLength = 40
    static let maximumWordCount = 5
    static let minimumConfidence: Float = 0.3
    static let maximumImageEdge: CGFloat = 1_600

    /// Runs text recognition on an independent screenshot and maps each line
    /// into a targetable element. Screenshot capture avoids retaining one of the
    /// live stream's IOSurface-backed buffers across asynchronous Vision work.
    static func recognize(
        image: CGImage,
        sourceFrame: CGRect,
        generation: Int
    ) async -> DemoElementIndex {
        let imageSize = CGSize(width: image.width, height: image.height)
        let contentRect = CGRect(origin: .zero, size: imageSize)
        guard contentRect.width > 0, contentRect.height > 0,
            sourceFrame.width > 0, sourceFrame.height > 0
        else {
            return DemoElementIndex(generation: generation, elements: [])
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(on: image)
        } catch {
            AppLog.demoMode.error(
                "Text recognition failed: \(error.localizedDescription, privacy: .public)"
            )
            return DemoElementIndex(generation: generation, elements: [])
        }

        var elements: [DemoElement] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first,
                candidate.confidence >= minimumConfidence
            else { continue }

            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                text.count <= maximumLabelLength,
                text.split(separator: " ").count <= maximumWordCount
            else { continue }

            let pixelRect = observation.boundingBox.toImageCoordinates(
                imageSize,
                origin: .upperLeft
            )
            guard
                let screenFrame = screenFrame(
                    fromPixelRect: pixelRect,
                    contentRect: contentRect,
                    sourceFrame: sourceFrame
                ),
                let bounds = AccessibilityElementIndexer.normalizedBounds(
                    of: screenFrame,
                    in: sourceFrame
                )
            else { continue }

            elements.append(
                DemoElement(
                    id: elements.count,
                    label: text,
                    role: .text,
                    source: .recognizedText,
                    normalizedBounds: bounds,
                    screenFrame: screenFrame,
                    pressable: false
                )
            )
        }
        return DemoElementIndex(generation: generation, elements: elements)
    }

    /// Maps a pixel-space rect inside the captured content back to global Quartz
    /// points by normalizing against the content region and projecting onto the
    /// source window frame.
    static func screenFrame(
        fromPixelRect pixelRect: CGRect,
        contentRect: CGRect,
        sourceFrame: CGRect
    ) -> CGRect? {
        guard contentRect.width > 0, contentRect.height > 0 else { return nil }
        let normalizedX = (pixelRect.minX - contentRect.minX) / contentRect.width
        let normalizedY = (pixelRect.minY - contentRect.minY) / contentRect.height
        let normalizedWidth = pixelRect.width / contentRect.width
        let normalizedHeight = pixelRect.height / contentRect.height

        return CGRect(
            x: sourceFrame.minX + normalizedX * sourceFrame.width,
            y: sourceFrame.minY + normalizedY * sourceFrame.height,
            width: normalizedWidth * sourceFrame.width,
            height: normalizedHeight * sourceFrame.height
        )
    }
}
