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

    mutating func observe(facePresent: Bool, visualState: HeadphoneVisualState) -> HeadphoneWearTransition {
        guard facePresent else {
            visibleSamples = 0
            absentSamples = 0
            return .none
        }

        switch visualState {
        case let .wearing(confidence) where confidence >= 0.48:
            visibleSamples += 1
            absentSamples = 0
            guard visibleSamples >= 2 else { return .none }
            let wasWearing = isWearing
            isWearing = true
            return wasWearing == false ? .putOn : .none
        case let .notWearing(confidence) where confidence >= 0.6:
            absentSamples += 1
            visibleSamples = 0
            guard absentSamples >= 2 else { return .none }
            let wasWearing = isWearing
            isWearing = false
            return wasWearing == true ? .removed : .none
        default:
            // A turned head or weak frame is not evidence of removal.
            visibleSamples = 0
            absentSamples = 0
            return .none
        }
    }
}
