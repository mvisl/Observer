import Foundation
import Vision

enum HeadphoneVisualState: Equatable {
    case unknown
    case wearing(Double)
    case notWearing(Double)
}

/// Learns the user's visible "headphones on" appearance locally in RAM. It stores
/// Vision feature vectors only, never frames. The camera is side-mounted, so
/// the profile learns the user's usual working angle instead of requiring a
/// frontal face.
struct HeadphoneAppearanceProfile {
    private struct WearingSample {
        let feature: VNFeaturePrintObservation
        let yaw: Double?
        let pitch: Double?
    }

    private var wearingFeatures: [WearingSample] = []
    private var withinProfileDistances: [Float] = []

    mutating func observe(
        jpegData: Data?,
        facePresent: Bool,
        faceCenterX: Double?,
        faceCenterY: Double?,
        faceArea: Double?,
        yaw: Double?,
        pitch: Double?,
        genericHeadphoneConfidence: Double?,
        audioOutputIndicatesHeadphones: Bool
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
        if genericConfidence >= 0.45 {
            learn(feature, yaw: yaw, pitch: pitch)
            return .wearing(min(0.92, genericConfidence + 0.12))
        }

        // A known headphone output lets the profile learn through intermittent
        // generic labels, but the output alone never generates a removal event.
        if audioOutputIndicatesHeadphones, wearingFeatures.count < 3 {
            learn(feature, yaw: yaw, pitch: pitch)
            return .wearing(0.58)
        }

        guard wearingFeatures.count >= 3,
              isComparableToProfile(yaw: yaw, pitch: pitch),
              let distance = nearestDistance(to: feature)
        else {
            return .unknown
        }

        let threshold = similarityThreshold
        if distance <= threshold {
            let confidence = min(0.86, max(0.48, 1 - Double(distance / max(threshold, 0.001)) * 0.45))
            if audioOutputIndicatesHeadphones {
                learn(feature, yaw: yaw, pitch: pitch)
            }
            return .wearing(confidence)
        }

        let distanceRatio = Double(distance / max(threshold, 0.001))
        return .notWearing(min(0.88, max(0.55, 0.5 + (distanceRatio - 1) * 0.2)))
    }

    private func isComparableToProfile(yaw: Double?, pitch: Double?) -> Bool {
        guard let yaw, let pitch else { return false }
        let poses = wearingFeatures.compactMap { sample -> (Double, Double)? in
            guard let sampleYaw = sample.yaw, let samplePitch = sample.pitch else { return nil }
            return (sampleYaw, samplePitch)
        }
        guard !poses.isEmpty else { return true }
        let meanYaw = poses.map(\.0).reduce(0, +) / Double(poses.count)
        let meanPitch = poses.map(\.1).reduce(0, +) / Double(poses.count)
        return abs(yaw - meanYaw) <= 0.30 && abs(pitch - meanPitch) <= 0.24
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

    private mutating func learn(_ feature: VNFeaturePrintObservation, yaw: Double?, pitch: Double?) {
        if let distance = nearestDistance(to: feature) {
            withinProfileDistances.append(distance)
            withinProfileDistances = Array(withinProfileDistances.suffix(20))
        }
        wearingFeatures.append(.init(feature: feature, yaw: yaw, pitch: pitch))
        wearingFeatures = Array(wearingFeatures.suffix(12))
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
