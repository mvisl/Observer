import Foundation
import Testing
@testable import ObserverApp

struct ReviewSamplerTests {
    @Test func picksTwoUncertainAndOneHighConfidenceSamples() {
        let events = [
            event(confidence: 0.45, cue: "friction_candidate"),
            event(confidence: 0.52, cue: "strong_reaction_candidate"),
            event(confidence: 0.82, cue: "steady_focus"),
            event(confidence: 0.2, cue: "ignored_low_confidence")
        ]

        let samples = ReviewSampler().eveningSamples(from: events)

        #expect(samples.count == 3)
        #expect(samples.filter { $0.reason == "active_learning" }.count == 2)
        #expect(samples.filter { $0.reason == "precision_control" }.count == 1)
    }

    private func event(confidence: Double, cue: String) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: Date(),
            type: .fusionHypothesis,
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
