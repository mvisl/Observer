import Foundation

enum HeadphoneWearTransition: Equatable {
    case none
    case removed
    case putOn
}

struct HeadphoneWearStateMachine {
    private(set) var isWearing: Bool?
    private let confirmationSeconds: TimeInterval
    private var wearingCandidateStartedAt: Date?
    private var removalCandidateStartedAt: Date?

    init(confirmationSeconds: TimeInterval = 5) {
        self.confirmationSeconds = confirmationSeconds
    }

    mutating func observe(
        facePresent: Bool,
        visualState: HeadphoneVisualState,
        now: Date = Date()
    ) -> HeadphoneWearTransition {
        guard facePresent else {
            wearingCandidateStartedAt = nil
            removalCandidateStartedAt = nil
            return .none
        }

        switch visualState {
        case let .wearing(confidence) where confidence >= 0.48:
            removalCandidateStartedAt = nil
            guard isWearing != true else { return .none }
            let startedAt = wearingCandidateStartedAt ?? now
            wearingCandidateStartedAt = startedAt
            guard now.timeIntervalSince(startedAt) >= confirmationSeconds else { return .none }
            let wasWearing = isWearing
            isWearing = true
            wearingCandidateStartedAt = nil
            return wasWearing == false ? .putOn : .none
        case let .notWearing(confidence) where confidence >= 0.6:
            wearingCandidateStartedAt = nil
            guard isWearing == true else { return .none }
            let startedAt = removalCandidateStartedAt ?? now
            removalCandidateStartedAt = startedAt
            guard now.timeIntervalSince(startedAt) >= confirmationSeconds else { return .none }
            let wasWearing = isWearing
            isWearing = false
            removalCandidateStartedAt = nil
            return wasWearing == true ? .removed : .none
        default:
            // A turned head, gaze change, or weak frame is not evidence of removal.
            wearingCandidateStartedAt = nil
            removalCandidateStartedAt = nil
            return .none
        }
    }
}
