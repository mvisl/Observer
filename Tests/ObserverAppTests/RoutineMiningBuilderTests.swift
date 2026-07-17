import Foundation
import Testing
@testable import ObserverApp

struct RoutineMiningBuilderTests {
    @Test func qualifiesGiphyToResizeOnlyAfterThreeIndependentCompletions() throws {
        let base = Date(timeIntervalSince1970: 1_784_000_000)
        let events = [
            event(.appFocus, base, app: "GIPHY Capture", payload: ["app_name": "GIPHY Capture"]),
            event(.screenContext, base.addingTimeInterval(90), payload: ["url_host": "ezgif.com"]),
            event(.appFocus, base.addingTimeInterval(3_000), app: "GIPHY Capture", payload: ["app_name": "GIPHY Capture"]),
            event(.screenContext, base.addingTimeInterval(3_120), payload: ["url_host": "reduceimages.com"]),
            event(.appFocus, base.addingTimeInterval(6_000), app: "GIPHY Capture", payload: ["app_name": "GIPHY Capture"]),
            event(.screenContext, base.addingTimeInterval(6_150), payload: ["url_host": "ezgif.com"])
        ]

        let candidates = RoutineMiningBuilder(settings: settings()).build(events: events)

        let candidate = try #require(candidates.first)
        #expect(candidate.routineKey == "capture:giphy>transform:resize")
        #expect(candidate.completionCount == 3)
        #expect(candidate.state == "shadow_qualified")
        #expect(candidate.payload["proposal_state"] == "not_proposed")
        #expect(candidate.payload["execution_state"] == "disabled")
        #expect(candidate.evidenceEventIDs.count == 6)
    }

    @Test func rejectsLateResizeAndDoesNotInferAOneOffRoutine() {
        let base = Date(timeIntervalSince1970: 1_784_000_000)
        let events = [
            event(.appFocus, base, app: "GIPHY Capture", payload: ["app_name": "GIPHY Capture"]),
            event(.screenContext, base.addingTimeInterval(1_500), payload: ["url_host": "ezgif.com"]),
            event(.appFocus, base.addingTimeInterval(3_000), app: "GIPHY Capture", payload: ["app_name": "GIPHY Capture"]),
            event(.screenContext, base.addingTimeInterval(3_090), payload: ["url_host": "ezgif.com"])
        ]

        #expect(RoutineMiningBuilder(settings: settings()).build(events: events).isEmpty)
    }

    private func settings() -> ObserverSettings.RoutineMiningSettings {
        .init(enabled: true, minimumCompletions: 3, maximumTransitionSeconds: 20 * 60, observationOnly: true)
    }

    private func event(
        _ type: ObserverEventType,
        _ timestamp: Date,
        app: String? = nil,
        payload: [String: String]
    ) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: timestamp,
            type: type,
            source: "test",
            platform: "macOS",
            displayRole: nil,
            appID: app,
            confidence: 0.9,
            payload: payload,
            workspaceTopologyVersion: 1
        )
    }
}
