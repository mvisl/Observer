import Foundation

struct ReviewSample: Equatable {
    let eventID: String
    let confidence: Double
    let reason: String
    let payload: [String: String]
}

struct ReviewSampler {
    func eveningSamples(from events: [ObserverEvent]) -> [ReviewSample] {
        let candidates = events
            .filter { $0.type == .fusionHypothesis || $0.type == .behaviorCue }
            .filter { $0.payload["cue"] != nil || $0.payload["interpretation"] != nil }

        let activeLearning = candidates
            .filter { $0.confidence >= 0.4 && $0.confidence <= 0.6 }
            .suffix(2)
            .map { sample(from: $0, reason: "active_learning") }

        let precisionControl = candidates
            .filter { $0.confidence > 0.75 }
            .suffix(1)
            .map { sample(from: $0, reason: "precision_control") }

        return Array(activeLearning + precisionControl)
    }

    private func sample(from event: ObserverEvent, reason: String) -> ReviewSample {
        ReviewSample(
            eventID: event.id.uuidString,
            confidence: event.confidence,
            reason: reason,
            payload: [
                "sample_event_id": event.id.uuidString,
                "sample_type": event.type.rawValue,
                "review_reason": reason,
                "confidence": String(format: "%.2f", event.confidence),
                "cue": event.payload["cue"] ?? "",
                "interpretation": event.payload["interpretation"] ?? "",
                "publication_state": event.payload["publication_state"] ?? ""
            ]
        )
    }
}
