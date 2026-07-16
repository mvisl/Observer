import Foundation

struct CameraCueQualityGate: Equatable {
    struct Settings: Equatable {
        let minimumFaceArea: Double
        let minimumBrightness: Double
        let maximumBrightness: Double
        let minimumSharpness: Double
    }

    enum Rejection: String, Equatable {
        case noFace = "no_face"
        case faceTooSmall = "face_too_small"
        case tooDark = "too_dark"
        case tooBright = "too_bright"
        case tooBlurry = "too_blurry"
    }

    func rejection(
        facePresent: Bool,
        faceArea: Double?,
        brightness: Double?,
        sharpness: Double?,
        settings: Settings
    ) -> Rejection? {
        guard facePresent else { return .noFace }
        guard (faceArea ?? 0) >= settings.minimumFaceArea else { return .faceTooSmall }
        guard let brightness else { return .tooDark }
        guard brightness >= settings.minimumBrightness else { return .tooDark }
        guard brightness <= settings.maximumBrightness else { return .tooBright }
        guard let sharpness, sharpness >= settings.minimumSharpness else { return .tooBlurry }
        return nil
    }
}

struct CameraCueRateLimiter: Equatable {
    enum Decision: Equatable {
        case suppressedByRefractory
        case emit(confidenceMultiplier: Double, selfThrottled: Bool)
    }

    private var emittedAtByCue: [String: [Date]] = [:]

    mutating func decide(
        cue: String,
        now: Date,
        refractorySeconds: TimeInterval,
        hourlyBudget: Int,
        throttledConfidenceMultiplier: Double
    ) -> Decision {
        let recent = (emittedAtByCue[cue] ?? []).filter { now.timeIntervalSince($0) < 3600 }
        emittedAtByCue[cue] = recent

        if let latest = recent.last, now.timeIntervalSince(latest) < refractorySeconds {
            return .suppressedByRefractory
        }

        let selfThrottled = recent.count >= hourlyBudget
        emittedAtByCue[cue, default: []].append(now)
        return .emit(
            confidenceMultiplier: selfThrottled ? throttledConfidenceMultiplier : 1,
            selfThrottled: selfThrottled
        )
    }
}
