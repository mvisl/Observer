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
        #expect(report.payload["blockers"]?.contains("pipeline integrity") == true)
        #expect(report.payload["blockers"]?.contains("episode readiness") == true)
    }

    @Test func funnelReportsEpisodeReadinessMetrics() {
        let now = Date()
        let start = now.addingTimeInterval(-120)
        let end = now.addingTimeInterval(-10)
        let iso = ISO8601DateFormatter()
        let events = [
            event(.attention, at: now, payload: ["face_present": "true"]),
            event(.inputActivity, at: now, payload: [:]),
            event(.contentContext, at: start.addingTimeInterval(10), payload: ["topic": "design conflict"]),
            event(.behaviorCue, at: now, payload: [:]),
            event(.fusionHypothesis, at: now, payload: [:]),
            event(.cognitiveState, at: now, payload: ["state": "engaged"]),
            event(.episode, at: now, payload: [
                "outcome": "applied",
                "start": iso.string(from: start),
                "end": iso.string(from: end)
            ]),
            event(.boundReaction, at: now, payload: ["topic": "design"])
        ]

        let report = ReadinessReportBuilder(
            settings: ObserverSettings.defaults.readinessSettings
        ).funnelReport(events: events, now: now)

        #expect(report.payload["today_episodes"] == "1")
        #expect(report.payload["today_independent_days"] == "1")
        #expect(report.payload["today_content_coverage"] == "1.000")
        #expect(report.payload["rolling_7d_episodes"] == "1")
        #expect(report.markdown.contains("not a raw event-count conversion funnel"))
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
