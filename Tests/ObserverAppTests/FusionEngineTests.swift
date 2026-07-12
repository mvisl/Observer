import Foundation
import Testing
@testable import ObserverApp

struct FusionEngineTests {
    @Test func keepsSingleChannelCandidateInShadow() {
        let now = Date()
        let candidate = event(
            type: .behaviorCue,
            timestamp: now,
            confidence: 0.62,
            payload: [
                "cue": "friction_candidate",
                "interpretation": "rapid_context_switching"
            ]
        )

        let decision = FusionEngine().decide(candidate: candidate, recentEvents: [candidate])

        #expect(decision.publicationState == "shadow")
        #expect(decision.surfaceAllowed == false)
        #expect(decision.payload["surface_allowed"] == "false")
    }

    @Test func publishesWhenIndependentChannelsAgree() {
        let now = Date()
        let candidate = event(
            type: .behaviorCue,
            timestamp: now,
            confidence: 0.48,
            payload: [
                "cue": "strong_reaction_candidate",
                "interpretation": "sudden_posture_change"
            ]
        )
        let textEvidence = event(
            type: .writingContext,
            timestamp: now.addingTimeInterval(-40),
            payload: ["context_kind": "active_writing"]
        )

        let decision = FusionEngine().decide(candidate: candidate, recentEvents: [textEvidence, candidate])

        #expect(decision.publicationState == "publishable")
        #expect(decision.surfaceAllowed == true)
        #expect(decision.channels.contains("camera"))
        #expect(decision.channels.contains("content"))
        #expect(decision.payload["surface_allowed"] == "true")
    }

    @Test func treatsYawnCandidateAsCameraEvidence() {
        let now = Date()
        let candidate = event(
            type: .behaviorCue,
            timestamp: now,
            confidence: 0.56,
            payload: [
                "cue": "energy_drop_candidate",
                "interpretation": "yawn_detected"
            ]
        )
        let inputEvidence = event(
            type: .inputActivity,
            timestamp: now.addingTimeInterval(-20),
            payload: ["seconds_since_any_input": "18"]
        )

        let decision = FusionEngine().decide(candidate: candidate, recentEvents: [inputEvidence, candidate])

        #expect(decision.publicationState == "publishable")
        #expect(decision.channels.contains("camera"))
        #expect(decision.channels.contains("input"))
    }

    @Test func objectPresenceCanSupportFusionWithoutSurfacingAlone() {
        let now = Date()
        let candidate = event(
            type: .behaviorCue,
            timestamp: now,
            confidence: 0.42,
            payload: [
                "cue": "wandering_candidate",
                "interpretation": "screen_static_input_idle"
            ]
        )
        let objectEvidence = event(
            type: .objectPresence,
            timestamp: now.addingTimeInterval(-10),
            payload: [
                "object_class": "cell phone",
                "in_hand": "true",
                "display_eligible": "false"
            ]
        )

        let decision = FusionEngine().decide(candidate: candidate, recentEvents: [objectEvidence, candidate])

        #expect(decision.publicationState == "publishable")
        #expect(decision.channels.contains("input"))
        #expect(decision.channels.contains("object"))
    }

    private func event(
        type: ObserverEventType,
        timestamp: Date,
        confidence: Double = 0.8,
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
            confidence: confidence,
            payload: payload,
            workspaceTopologyVersion: 1
        )
    }
}
