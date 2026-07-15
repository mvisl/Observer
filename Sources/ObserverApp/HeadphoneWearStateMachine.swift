import Foundation

enum HeadphoneWearTransition: Equatable {
    case none
    case removed
    case putOn
}

struct HeadphoneWearStateMachine {
    private(set) var isWearing: Bool?
    private var visibleSamples = 0
    private var absentSamples = 0

    mutating func observe(facePresent: Bool, headphoneConfidence: Double?) -> HeadphoneWearTransition {
        guard facePresent else {
            visibleSamples = 0
            absentSamples = 0
            return .none
        }

        if (headphoneConfidence ?? 0) >= 0.35 {
            visibleSamples += 1
            absentSamples = 0
            guard visibleSamples >= 2 else { return .none }
            let wasWearing = isWearing
            isWearing = true
            return wasWearing == false ? .putOn : .none
        }

        absentSamples += 1
        visibleSamples = 0
        // Camera attention arrives every five seconds. Two consistent samples
        // keep the response prompt without turning a transient occlusion into
        // a pause; a missing face is handled above as a separate away signal.
        guard absentSamples >= 2 else { return .none }
        let wasWearing = isWearing
        isWearing = false
        return wasWearing == true ? .removed : .none
    }
}
