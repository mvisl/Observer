import Foundation

enum HeadphoneOutputTransition: Equatable {
    case none
    case removed
    case returned
}

/// Audio routing is a stronger signal than the generic camera classifier. A single
/// transient route report must never pause media, so removal needs two stable probes.
struct HeadphoneOutputTransitionGate {
    private let confirmationSeconds: TimeInterval
    private var lastLooksLikeHeadphones: Bool?
    private var removalCandidateStartedAt: Date?

    init(confirmationSeconds: TimeInterval = 20) {
        self.confirmationSeconds = confirmationSeconds
    }

    mutating func observe(outputLooksLikeHeadphones: Bool?, now: Date) -> HeadphoneOutputTransition {
        guard let outputLooksLikeHeadphones else {
            removalCandidateStartedAt = nil
            return .none
        }

        guard let previous = lastLooksLikeHeadphones else {
            lastLooksLikeHeadphones = outputLooksLikeHeadphones
            return .none
        }

        if previous == outputLooksLikeHeadphones {
            guard outputLooksLikeHeadphones == false,
                  let startedAt = removalCandidateStartedAt,
                  now.timeIntervalSince(startedAt) >= confirmationSeconds
            else {
                return .none
            }
            removalCandidateStartedAt = nil
            return .removed
        }

        lastLooksLikeHeadphones = outputLooksLikeHeadphones
        if outputLooksLikeHeadphones {
            removalCandidateStartedAt = nil
            return .returned
        }

        removalCandidateStartedAt = now
        return .none
    }

    mutating func reset() {
        lastLooksLikeHeadphones = nil
        removalCandidateStartedAt = nil
    }
}
