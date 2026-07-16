import Foundation
import Vision

enum HeadphoneVisualState: Equatable {
    case unknown
    case wearing(Double)
    case notWearing(Double)
}

/// Learns the user's visible "headphones on" appearance locally in RAM. It stores
/// Vision feature vectors only, never frames. The crop is face-relative, and
/// matching deliberately ignores gaze and head angle: headphones must be
/// recognised while the person reads, looks aside, or sits at a different angle.
struct HeadphoneAppearanceProfile {
    private struct WearingSample {
        let feature: VNFeaturePrintObservation
    }

    private var wearingFeatures: [WearingSample] = []
    private var withinProfileDistances: [Float] = []

    mutating func observe(
        jpegData: Data?,
        facePresent: Bool,
        faceCenterX: Double?,
        faceCenterY: Double?,
        faceArea: Double?,
        genericHeadphoneConfidence: Double?,
        audioOutputIndicatesHeadphones: Bool,
        audioIsActive: Bool,
        confirmedWearing: Bool
    ) -> HeadphoneVisualState {
        guard facePresent, let jpegData,
              let feature = featurePrint(
                from: jpegData,
                faceCenterX: faceCenterX,
                faceCenterY: faceCenterY,
                faceArea: faceArea
              )
        else {
            return .unknown
        }

        let genericConfidence = genericHeadphoneConfidence ?? 0

        // Bootstrapping only establishes an initial positive profile. It never
        // creates a removal event, because wired and Bluetooth routes can remain
        // selected after the headphones leave the user's head.
        if audioOutputIndicatesHeadphones, audioIsActive, wearingFeatures.count < 3 {
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
            // The generic Vision classifier is useful as corroborating evidence,
            // but never as the deciding signal: it has repeatedly called an
            // empty head "headphones" in this camera setup. Keep learning views
            // only when they already resemble the owner's established profile.
            if confirmedWearing || genericConfidence >= 0.20 {
                learn(feature)
            }
            let confidence = min(0.86, max(0.48, 1 - Double(distance / max(threshold, 0.001)) * 0.45))
            return .wearing(confidence)
        }

        // This is a comparison with the whole accumulated appearance profile,
        // not a pose bucket. A new head angle is only a removal candidate when
        // it has no visual resemblance to any learned headphone view.
        let distanceRatio = Double(distance / max(threshold, 0.001))
        return .notWearing(min(0.88, max(0.55, 0.5 + (distanceRatio - 1) * 0.2)))
    }

    private func featurePrint(
        from jpegData: Data,
        faceCenterX: Double?,
        faceCenterY: Double?,
        faceArea: Double?
    ) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.regionOfInterest = headAndEarRegion(
            centerX: faceCenterX,
            centerY: faceCenterY,
            faceArea: faceArea
        )
        let handler = VNImageRequestHandler(data: jpegData, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    private func headAndEarRegion(centerX: Double?, centerY: Double?, faceArea: Double?) -> CGRect {
        guard let centerX, let centerY, let faceArea, faceArea > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let faceSide = sqrt(faceArea)
        let width = min(1, max(0.34, faceSide * 3.0))
        let height = min(1, max(0.30, faceSide * 2.2))
        let x = min(max(0, centerX - width / 2), 1 - width)
        let y = min(max(0, centerY - height / 2), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private mutating func learn(_ feature: VNFeaturePrintObservation) {
        if let distance = nearestDistance(to: feature) {
            withinProfileDistances.append(distance)
            withinProfileDistances = Array(withinProfileDistances.suffix(20))
        }
        wearingFeatures.append(.init(feature: feature))
        // Keep enough views for side-on, upright, leaning and downward reading
        // positions. A short rolling profile was silently forgetting them.
        wearingFeatures = Array(wearingFeatures.suffix(48))
    }

    private func nearestDistance(to feature: VNFeaturePrintObservation) -> Float? {
        wearingFeatures.compactMap { sample in
            var distance: Float = 0
            guard (try? feature.computeDistance(&distance, to: sample.feature)) != nil else {
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
