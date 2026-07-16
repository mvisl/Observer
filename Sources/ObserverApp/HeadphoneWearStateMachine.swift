import Foundation

enum HeadphoneWearTransition: Equatable {
    case none
    case removed
    case putOn
}

struct HeadphoneWearStateMachine {
    private(set) var isWearing: Bool?
    private let confirmationSeconds: TimeInterval
    private let unknownGraceSeconds: TimeInterval
    private var wearingCandidateStartedAt: Date?
    private var removalCandidateStartedAt: Date?
    private var lastRemovalEvidenceAt: Date?

    init(confirmationSeconds: TimeInterval = 5, unknownGraceSeconds: TimeInterval = 2) {
        self.confirmationSeconds = confirmationSeconds
        self.unknownGraceSeconds = unknownGraceSeconds
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
            lastRemovalEvidenceAt = nil
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
            lastRemovalEvidenceAt = now
            guard now.timeIntervalSince(startedAt) >= confirmationSeconds else { return .none }
            let wasWearing = isWearing
            isWearing = false
            removalCandidateStartedAt = nil
            return wasWearing == true ? .removed : .none
        default:
            // A brief blur while the person is moving the headphones must not
            // reset a genuine removal trajectory. Face loss still resets it.
            wearingCandidateStartedAt = nil
            if let lastRemovalEvidenceAt,
               now.timeIntervalSince(lastRemovalEvidenceAt) <= unknownGraceSeconds {
                return .none
            }
            removalCandidateStartedAt = nil
            self.lastRemovalEvidenceAt = nil
            return .none
        }
    }
}
