import Testing
@testable import ObserverApp

struct DetectorEngineTests {
    @Test func detectsFrequentAppSwitching() {
        let events = (0..<8).map { index in
            ObserverEvent(
                type: .appFocus,
                appID: "app.\(index % 2)",
                payload: ["app_name": index % 2 == 0 ? "Design" : "Browser"],
                workspaceTopologyVersion: 1
            )
        }

        let detections = DetectorEngine().evaluate(events: events)
        #expect(detections.contains { $0.name == "frequent_app_switching" })
    }

    @Test func detectsReadingOrThinkingPause() {
        let events = [
            ObserverEvent(
                type: .inputActivity,
                payload: ["seconds_since_any_input": "240"],
                workspaceTopologyVersion: 1
            ),
            ObserverEvent(
                type: .attention,
                payload: ["face_present": "true"],
                workspaceTopologyVersion: 1
            )
        ]

        let detections = DetectorEngine().evaluate(events: events)
        #expect(detections.contains { $0.name == "reading_or_thinking" })
    }
}
