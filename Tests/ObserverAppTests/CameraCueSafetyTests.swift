import Foundation
import Testing
@testable import ObserverApp

struct CameraCueSafetyTests {
    @Test func rejectsEmotionalCandidateWhenFaceOrFrameIsUnreliable() {
        let gate = CameraCueQualityGate()
        let settings = CameraCueQualityGate.Settings(
            minimumFaceArea: 0.012,
            minimumBrightness: 0.08,
            maximumBrightness: 0.92,
            minimumSharpness: 0.006
        )

        #expect(gate.rejection(facePresent: false, faceArea: nil, brightness: 0.5, sharpness: 0.1, settings: settings) == .noFace)
        #expect(gate.rejection(facePresent: true, faceArea: 0.004, brightness: 0.5, sharpness: 0.1, settings: settings) == .faceTooSmall)
        #expect(gate.rejection(facePresent: true, faceArea: 0.04, brightness: 0.03, sharpness: 0.1, settings: settings) == .tooDark)
        #expect(gate.rejection(facePresent: true, faceArea: 0.04, brightness: 0.5, sharpness: 0.001, settings: settings) == .tooBlurry)
        #expect(gate.rejection(facePresent: true, faceArea: 0.04, brightness: 0.5, sharpness: 0.1, settings: settings) == nil)
    }

    @Test func mergesRepeatedCueAndThrottlesNoisyDetector() {
        var limiter = CameraCueRateLimiter()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(limiter.decide(cue: "smile", now: start, refractorySeconds: 60, hourlyBudget: 2, throttledConfidenceMultiplier: 0.55) == .emit(confidenceMultiplier: 1, selfThrottled: false))
        #expect(limiter.decide(cue: "smile", now: start.addingTimeInterval(30), refractorySeconds: 60, hourlyBudget: 2, throttledConfidenceMultiplier: 0.55) == .suppressedByRefractory)
        #expect(limiter.decide(cue: "smile", now: start.addingTimeInterval(61), refractorySeconds: 60, hourlyBudget: 2, throttledConfidenceMultiplier: 0.55) == .emit(confidenceMultiplier: 1, selfThrottled: false))
        #expect(limiter.decide(cue: "smile", now: start.addingTimeInterval(122), refractorySeconds: 60, hourlyBudget: 2, throttledConfidenceMultiplier: 0.55) == .emit(confidenceMultiplier: 0.55, selfThrottled: true))
    }
}
