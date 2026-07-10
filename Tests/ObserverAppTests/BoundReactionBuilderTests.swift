import Foundation
import Testing
@testable import ObserverApp

struct BoundReactionBuilderTests {
    @Test func bindsCueToNearbyContentContext() {
        let now = Date()
        let cue = event(
            type: .behaviorCue,
            timestamp: now,
            payload: ["cue": "positive_reaction_candidate", "interpretation": "smile"]
        )
        let content = event(
            type: .contentContext,
            timestamp: now.addingTimeInterval(-2),
            payload: [
                "source_entity_id": "person_abc",
                "topic": "сообщение от жены",
                "sentiment": "pos",
                "content_kind": "message"
            ]
        )

        let payload = BoundReactionBuilder().build(cueEvent: cue, recentEvents: [content, cue])

        #expect(payload?["entity_id"] == "person_abc")
        #expect(payload?["topic"] == "сообщение от жены")
        #expect(payload?["cue"] == "positive_reaction_candidate")
    }

    private func event(
        type: ObserverEventType,
        timestamp: Date,
        payload: [String: String]
    ) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: timestamp,
            type: type,
            source: "test",
            platform: "macOS",
            displayRole: nil,
            appID: nil,
            confidence: 0.8,
            payload: payload,
            workspaceTopologyVersion: 1
        )
    }
}
