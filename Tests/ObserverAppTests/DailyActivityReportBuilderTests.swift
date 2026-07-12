import Foundation
import Testing
@testable import ObserverApp

struct DailyActivityReportBuilderTests {
    @Test func reportsAssignedUnassignedAndDoesNotCreateActions() {
        let now = Date()
        let assignedThread = event(.activityThread, at: now, confidence: 0.8, payload: [
            "activity_thread_id": "thread-a",
            "generated_name": "Observer — context fabric",
            "confidence": "0.80",
            "source_event_ids": UUID().uuidString
        ])
        let assignedSlice = event(.contextSlice, at: now.addingTimeInterval(60), confidence: 0.8, payload: [
            "activity_thread_id": "thread-a",
            "assignment_state": "assigned",
            "activity_kind": "ai_assisted",
            "started_at": ISO8601DateFormatter().string(from: now),
            "ended_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(600)),
            "active_seconds": "600",
            "source_event_ids": assignedThread.id.uuidString
        ])
        let unassignedSlice = event(.contextSlice, at: now.addingTimeInterval(700), confidence: 0.3, payload: [
            "activity_thread_id": "",
            "assignment_state": "unassigned",
            "activity_kind": "unknown",
            "started_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(700)),
            "ended_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(1000)),
            "active_seconds": "300",
            "source_event_ids": assignedThread.id.uuidString
        ])

        let result = DailyActivityReportBuilder().build(
            events: [assignedThread, assignedSlice, unassignedSlice],
            day: now
        )

        #expect(result.diagnostics["assigned_active_seconds"] == "600.0")
        #expect(result.diagnostics["unassigned_active_seconds"] == "300.0")
        #expect(result.diagnostics["tracker_actions_enabled"] == "false")
        #expect(result.diagnostics["tracker_external_sending_enabled"] == "false")
        #expect(result.markdown.contains("Observer — context fabric"))
    }

    @Test func replayDatasetContainsRequiredFortyScenariosWithForbiddenAssignments() {
        let fixtures = ContextFabricReplayDataset.fixtures

        #expect(fixtures.count >= 40)
        #expect(Set(fixtures.map(\.id)).count == fixtures.count)
        #expect(fixtures.allSatisfy { !$0.expectedObservations.isEmpty })
        #expect(fixtures.allSatisfy { !$0.forbiddenAssignments.isEmpty })
        #expect(fixtures.contains { $0.name == "same_frame_multiple_cues" })
        #expect(fixtures.contains { $0.name == "idempotent_rebuild" })
    }

    private func event(
        _ type: ObserverEventType,
        at date: Date,
        confidence: Double,
        payload: [String: String]
    ) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: date,
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
