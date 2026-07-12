import Foundation
import Testing
@testable import ObserverApp

struct ReadinessReportBuilderTests {
    @Test func reportsNotReadyWhenMinimumEvidenceIsMissing() {
        let now = Date()
        let events = [
            event(.attention, at: now.addingTimeInterval(-50), payload: ["face_present": "true"]),
            event(.inputActivity, at: now.addingTimeInterval(-40), payload: ["seconds_since_any_input": "1"]),
            event(.contentContext, at: now.addingTimeInterval(-30), payload: ["topic": "design conflict"]),
            event(.behaviorCue, at: now.addingTimeInterval(-20), payload: ["cue": "friction_candidate"]),
            event(.fusionHypothesis, at: now.addingTimeInterval(-10), payload: ["publication_state": "publishable"])
        ]

        let report = ReadinessReportBuilder(
            settings: ObserverSettings.defaults.readinessSettings
        ).readinessReport(events: events, now: now)

        #expect(report.isReadyForPrediction == false)
        #expect(report.payload["status"] == "not_ready")
        #expect(report.payload["blockers"]?.contains("cognitiveState") == true)
        #expect(report.payload["blockers"]?.contains("boundReaction") == true)
    }

    @Test func funnelCountsTheBrainConversionStages() {
        let now = Date()
        let events = [
            event(.attention, at: now, payload: ["face_present": "true"]),
            event(.inputActivity, at: now, payload: [:]),
            event(.contentContext, at: now, payload: [:]),
            event(.behaviorCue, at: now, payload: [:]),
            event(.fusionHypothesis, at: now, payload: [:]),
            event(.cognitiveState, at: now, payload: ["state": "engaged"]),
            event(.episode, at: now, payload: ["outcome": "applied"]),
            event(.boundReaction, at: now, payload: ["topic": "design"])
        ]

        let report = ReadinessReportBuilder(
            settings: ObserverSettings.defaults.readinessSettings
        ).funnelReport(events: events, now: now)

        #expect(report.payload["today_signals"] == "3")
        #expect(report.payload["today_behavior_cues"] == "1")
        #expect(report.payload["today_fusion_hypotheses"] == "1")
        #expect(report.payload["today_cognitive_states"] == "1")
        #expect(report.payload["today_episode_outcomes"] == "1")
        #expect(report.payload["today_bound_reactions"] == "1")
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
