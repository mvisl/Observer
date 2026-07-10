import Foundation
import Testing
@testable import ObserverApp

struct ReviewSamplerTests {
    @Test func picksTwoUncertainAndOneHighConfidenceSamples() {
        let events = [
            event(confidence: 0.45, cue: "friction_candidate"),
            event(confidence: 0.52, cue: "strong_reaction_candidate"),
            event(confidence: 0.82, cue: "steady_focus"),
            event(confidence: 0.2, cue: "ignored_low_confidence"),
            event(type: .boundReaction, confidence: 0.7, cue: "positive_reaction_candidate")
        ]

        let samples = ReviewSampler().eveningSamples(from: events)

        #expect(samples.count == 4)
        #expect(samples.filter { $0.reason == "active_learning" }.count == 2)
        #expect(samples.filter { $0.reason == "precision_control" }.count == 1)
        #expect(samples.filter { $0.reason == "reaction_binding_check" }.count == 1)
    }

    private func event(
        type: ObserverEventType = .fusionHypothesis,
        confidence: Double,
        cue: String
    ) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: Date(),
            type: type,
            source: "test",
            platform: "macOS",
            displayRole: nil,
            appID: nil,
            confidence: confidence,
            payload: [
                "cue": cue,
                "interpretation": cue,
                "publication_state": "publishable"
            ],
            workspaceTopologyVersion: 1
        )
    }
}
