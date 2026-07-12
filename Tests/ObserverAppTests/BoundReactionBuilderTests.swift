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

    @Test func marksReactionAmbiguousWhenMusicIsPlayingNearby() {
        let now = Date()
        let cue = event(
            type: .behaviorCue,
            timestamp: now,
            payload: ["cue": "positive_reaction_candidate", "interpretation": "smile"]
        )
        let content = event(
            type: .contentContext,
            timestamp: now.addingTimeInterval(-1),
            payload: [
                "source_entity_id": "person_abc",
                "topic": "лёгкая переписка",
                "content_kind": "message"
            ]
        )
        let media = event(
            type: .mediaPlayback,
            timestamp: now.addingTimeInterval(-2),
            payload: [
                "state": "playing",
                "source": "Music",
                "artist": "Janko Nilovic",
                "title": "Through The Fingers"
            ]
        )

        let payload = BoundReactionBuilder().build(cueEvent: cue, recentEvents: [media, content, cue])

        #expect(payload?["competing_evidence"] == "media_playback")
        #expect(payload?["attribution"] == "ambiguous_content_vs_media")
        #expect(payload?["media_title"] == "Through The Fingers")
        #expect(payload?["evidence_event_ids"]?.contains(media.id.uuidString) == true)
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
