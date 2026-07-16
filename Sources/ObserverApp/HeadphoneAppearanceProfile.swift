import Foundation
import Vision

enum HeadphoneVisualState: Equatable {
    case unknown
    case wearing(Double)
    case notWearing(Double)
}

/// Learns the user's visible "headphones on" appearance locally in RAM. It stores
/// Vision feature vectors only, never frames, and refuses to judge side turns.
struct HeadphoneAppearanceProfile {
    private var wearingFeatures: [VNFeaturePrintObservation] = []
    private var withinProfileDistances: [Float] = []

    mutating func observe(
        jpegData: Data?,
        facePresent: Bool,
        yaw: Double?,
        pitch: Double?,
        genericHeadphoneConfidence: Double?,
        audioOutputIndicatesHeadphones: Bool
    ) -> HeadphoneVisualState {
        guard facePresent, isComparablePose(yaw: yaw, pitch: pitch), let jpegData,
              let feature = featurePrint(from: jpegData)
        else {
            return .unknown
        }

        let genericConfidence = genericHeadphoneConfidence ?? 0
        if genericConfidence >= 0.45 {
            learn(feature)
            return .wearing(min(0.92, genericConfidence + 0.12))
        }

        // A known headphone output lets the profile learn through intermittent
        // generic labels, but the output alone never generates a removal event.
        if audioOutputIndicatesHeadphones, wearingFeatures.count < 3 {
            learn(feature)
            return .wearing(0.58)
        }

        guard wearingFeatures.count >= 3,
              let distance = nearestDistance(to: feature)
        else {
            return .unknown
        }

        let threshold = similarityThreshold
        if distance <= threshold {
            let confidence = min(0.86, max(0.48, 1 - Double(distance / max(threshold, 0.001)) * 0.45))
            if audioOutputIndicatesHeadphones {
                learn(feature)
            }
            return .wearing(confidence)
        }

        let distanceRatio = Double(distance / max(threshold, 0.001))
        return .notWearing(min(0.88, max(0.55, 0.5 + (distanceRatio - 1) * 0.2)))
    }

    private func isComparablePose(yaw: Double?, pitch: Double?) -> Bool {
        guard let yaw, let pitch else { return false }
        return abs(yaw) <= 0.35 && abs(pitch) <= 0.28
    }

    private func featurePrint(from jpegData: Data) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(data: jpegData, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    private mutating func learn(_ feature: VNFeaturePrintObservation) {
        if let distance = nearestDistance(to: feature) {
            withinProfileDistances.append(distance)
            withinProfileDistances = Array(withinProfileDistances.suffix(20))
        }
        wearingFeatures.append(feature)
        wearingFeatures = Array(wearingFeatures.suffix(12))
    }

    private func nearestDistance(to feature: VNFeaturePrintObservation) -> Float? {
        wearingFeatures.compactMap { existing in
            var distance: Float = 0
            guard (try? feature.computeDistance(&distance, to: existing)) != nil else {
                return nil
            }
            return distance
        }.min()
    }

    private var similarityThreshold: Float {
        guard !withinProfileDistances.isEmpty else { return 12 }
        let sorted = withinProfileDistances.sorted()
        let percentileIndex = Int(Double(sorted.count - 1) * 0.8)
        return max(2, sorted[percentileIndex] * 1.8 + 0.5)
    }
}
