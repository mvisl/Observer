import Foundation
import Testing
@testable import ObserverApp

struct CausalUnderstandingBuilderTests {
    @Test func createsCorrectionLoopHypothesisOnlyWithTransitionMechanismAndAlternative() throws {
        let now = Date()
        let start = now.addingTimeInterval(-180)
        let correction = event(
            .contentContext,
            at: now.addingTimeInterval(-80),
            payload: [
                "topic": "Observer pill quality",
                "raw_fragment": "это санитарное поверхностное сообщение, нужен уровень выше"
            ]
        )
        let input = event(.inputActivity, at: now.addingTimeInterval(-70), payload: ["seconds_since_any_input": "1"])
        let episode = event(
            .episode,
            at: now,
            payload: [
                "episode_kind": "ai_assisted_work",
                "start": ISO8601DateFormatter().string(from: start),
                "end": ISO8601DateFormatter().string(from: now),
                "topic": "Observer pill quality",
                "goal": "улучшить смысловую глубину Observer",
                "outcome": "closed",
                "trace_event_ids": [correction.id.uuidString, input.id.uuidString].joined(separator: ",")
            ]
        )

        let result = CausalUnderstandingBuilder().buildForClosedEpisode(
            episode: episode,
            episodeEvents: [correction, input],
            historicalEvents: [correction, input],
            now: now
        )

        #expect(result.transitions.first?["transition_type"] == "correction_loop_started")
        #expect(result.antecedents.contains { $0["role"] == "trigger" })
        let hypothesis = try #require(result.hypotheses.first)
        #expect(hypothesis["mechanism"]?.contains("уровень абстракции") == true)
        #expect(hypothesis["alternative_claims"]?.contains("технический баг") == true)
        #expect(hypothesis["maturity_level"] == "plausible_mechanism")
        #expect(hypothesis["not_user_visible"] == "true")
    }

    @Test func doesNotCreateCausalHypothesisForStaticStateOnly() {
        let now = Date()
        let stateEvent = event(.cognitiveState, at: now, payload: ["state": "engaged"])
        let episode = event(
            .episode,
            at: now,
            payload: [
                "episode_kind": "mixed",
                "start": ISO8601DateFormatter().string(from: now.addingTimeInterval(-120)),
                "end": ISO8601DateFormatter().string(from: now),
                "outcome": "closed",
                "trace_event_ids": stateEvent.id.uuidString
            ]
        )

        let result = CausalUnderstandingBuilder().buildForClosedEpisode(
            episode: episode,
            episodeEvents: [stateEvent],
            now: now
        )

        #expect(result.transitions.isEmpty)
        #expect(result.hypotheses.isEmpty)
    }

    @Test func replayDatasetContainsAtLeastTwentyFiveGuardedFixtures() {
        #expect(CausalReplayDataset.fixtures.count >= 25)
        #expect(CausalReplayDataset.fixtures.allSatisfy { !$0.requiredAlternative.isEmpty })
        #expect(CausalReplayDataset.fixtures.allSatisfy { !$0.forbiddenCausalClaims.isEmpty })
    }

    @Test func userVisiblePolicyBlocksLowLevelAndLegacyOutputs() {
        let valid: [String: String] = [
            "pipeline_version": ObserverPipeline.version,
            "session_id": "session",
            "episode_id": "episode",
            "source_event_ids": "source",
            "abstraction_level": "L2"
        ]
        #expect(UserVisibleOutputPolicy.validate(payload: valid) == .allowed)

        var low = valid
        low["abstraction_level"] = "L1"
        #expect(UserVisibleOutputPolicy.validate(payload: low) == .lowAbstraction)

        var legacy = valid
        legacy["primary_source_type"] = ObserverEventType.activityInsight.rawValue
        #expect(UserVisibleOutputPolicy.validate(payload: legacy) == .legacyPrimarySource)

        var noEvidence = valid
        noEvidence["source_event_ids"] = ""
        #expect(UserVisibleOutputPolicy.validate(payload: noEvidence) == .missingEvidence)
    }

    private func event(
        _ type: ObserverEventType,
        at timestamp: Date,
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
