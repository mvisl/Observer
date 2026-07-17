import Foundation
import Vision

/// Keeps an in-memory profile of the owner from actively used frames. It compares
/// only a face-relative crop: a perceptual hash of the whole office frame made
/// different people at the same desk look like the owner.
final class OwnerFaceRecognizer {
    private var ownerFeatures: [VNFeaturePrintObservation] = []
    private var withinProfileDistances: [Float] = []
    private let maximumFeatures = 48
    private let minimumProfileSize = 6

    var hasProfile: Bool {
        ownerFeatures.count >= minimumProfileSize
    }

    func learnOwnerFace(from attention: AttentionSnapshot) {
        guard attention.facePresent,
              attention.faceCount == 1,
              let feature = featurePrint(from: attention)
        else {
            return
        }

        if let distance = nearestDistance(to: feature) {
            withinProfileDistances.append(distance)
            withinProfileDistances = Array(withinProfileDistances.suffix(32))
        }
        ownerFeatures.append(feature)
        ownerFeatures = Array(ownerFeatures.suffix(maximumFeatures))
    }

    /// Returns true only for a high-quality, single-face match. Unknown is never
    /// treated as an owner match, because missing a visitor is worse than asking
    /// the owner to review a local security snapshot.
    func isOwnerFace(_ attention: AttentionSnapshot) -> Bool? {
        guard attention.facePresent,
              attention.faceCount == 1,
              (attention.faceArea ?? 0) >= 0.012,
              ownerFeatures.count >= minimumProfileSize,
              let feature = featurePrint(from: attention),
              let distance = nearestDistance(to: feature)
        else {
            return nil
        }
        return distance <= similarityThreshold
    }

    private func featurePrint(from attention: AttentionSnapshot) -> VNFeaturePrintObservation? {
        guard let jpegData = attention.jpegData else {
            return nil
        }
        let request = VNGenerateImageFeaturePrintRequest()
        request.regionOfInterest = faceRegion(
            centerX: attention.faceCenterX,
            centerY: attention.faceCenterY,
            faceArea: attention.faceArea
        )
        let handler = VNImageRequestHandler(data: jpegData, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    private func faceRegion(centerX: Double?, centerY: Double?, faceArea: Double?) -> CGRect {
        guard let centerX, let centerY, let faceArea, faceArea > 0 else {
            return .zero
        }
        let faceSide = sqrt(faceArea)
        let width = min(1, max(0.16, faceSide * 1.35))
        let height = min(1, max(0.18, faceSide * 1.55))
        let x = min(max(0, centerX - width / 2), 1 - width)
        let y = min(max(0, centerY - height / 2), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func nearestDistance(to feature: VNFeaturePrintObservation) -> Float? {
        ownerFeatures.compactMap { sample in
            var distance: Float = 0
            guard (try? feature.computeDistance(&distance, to: sample)) != nil else {
                return nil
            }
            return distance
        }.min()
    }

    private var similarityThreshold: Float {
        guard !withinProfileDistances.isEmpty else {
            return 5
        }
        let sorted = withinProfileDistances.sorted()
        let percentileIndex = Int(Double(sorted.count - 1) * 0.8)
        return max(2, sorted[percentileIndex] * 1.55 + 0.4)
    }
}
