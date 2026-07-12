import Foundation
import Testing
@testable import ObserverApp

@Suite("DashboardReadModelBuilderTests")
struct DashboardReadModelBuilderTests {
    @Test
    func buildsValidDaySnapshotWithAssignedAndUnassignedTotals() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 10))!
        let assignedThreadID = UUID().uuidString
        let episodeID = UUID().uuidString
        let thread = event(
            type: .activityThread,
            at: day,
            payload: [
                "activity_thread_id": assignedThreadID,
                "generated_name": "Observer — Daily Activity Report",
                "confidence": "0.86"
            ]
        )
        let episode = event(
            id: UUID(uuidString: episodeID)!,
            type: .episode,
            at: day.addingTimeInterval(60),
            payload: [
                "apps": "ChatGPT -> Figma",
                "goal": "Перестроить отчёт вокруг задач",
                "duration_seconds": "600"
            ]
        )
        let assigned = event(
            type: .contextSlice,
            at: day.addingTimeInterval(120),
            payload: [
                "started_at": ISO8601DateFormatter().string(from: day.addingTimeInterval(120)),
                "ended_at": ISO8601DateFormatter().string(from: day.addingTimeInterval(420)),
                "active_seconds": "300",
                "activity_thread_id": assignedThreadID,
                "assignment_state": "assigned",
                "activity_kind": "ai_assisted_work",
                "episode_event_id": episodeID,
                "confidence": "0.82"
            ]
        )
        let unassigned = event(
            type: .contextSlice,
            at: day.addingTimeInterval(600),
            payload: [
                "started_at": ISO8601DateFormatter().string(from: day.addingTimeInterval(600)),
                "ended_at": ISO8601DateFormatter().string(from: day.addingTimeInterval(720)),
                "active_seconds": "120",
                "assignment_state": "unassigned",
                "activity_kind": "communication",
                "confidence": "0.30"
            ]
        )

        let snapshot = DashboardReadModelBuilder().buildDaySnapshot(
            events: [thread, episode, assigned, unassigned],
            date: day,
            timezone: TimeZone(secondsFromGMT: 0)!,
            settings: .defaults
        )

        #expect(snapshot.valid)
        #expect(snapshot.totals.assignedSeconds == 300)
        #expect(snapshot.totals.unassignedSeconds == 120)
        #expect(snapshot.totals.attributableSeconds == 420)
        #expect(snapshot.threadSummaries.first?.name == "Observer — Daily Activity Report")
        #expect(snapshot.reviewSummary.unassigned == 1)
    }

    @Test
    func exposesSensorChannelsWithoutRawPayloads() {
        let now = Date()
        let snapshot = DashboardReadModelBuilder().buildDaySnapshot(
            events: [
                event(type: .attention, at: now, payload: ["face_present": "true"]),
                event(type: .contentContext, at: now, payload: ["topic": "Observer report"]),
                event(type: .inputActivity, at: now, payload: ["event": "typing"])
            ],
            date: now,
            settings: .defaults
        )

        let channelNames = Set(snapshot.sensorSummary.channels.map(\.name))
        #expect(channelNames.contains("Camera"))
        #expect(channelNames.contains("Content"))
        #expect(channelNames.contains("Input"))
    }

    private func event(
        id: UUID = UUID(),
        type: ObserverEventType,
        at date: Date,
        payload: [String: String]
    ) -> ObserverEvent {
        ObserverEvent(
            id: id,
            timestamp: date,
            type: type,
            source: "test",
            platform: "macOS",
            displayRole: nil,
            appID: nil,
            confidence: Double(payload["confidence"] ?? "1") ?? 1,
            payload: payload,
            workspaceTopologyVersion: 1
        )
    }
}
