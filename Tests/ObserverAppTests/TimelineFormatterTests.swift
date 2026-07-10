import Testing
@testable import ObserverApp

struct TimelineFormatterTests {
    @Test func formatsUserNotes() {
        let event = ObserverEvent(
            type: .userNote,
            payload: ["note": "remember this"],
            workspaceTopologyVersion: 1
        )

        let timeline = TimelineFormatter().format(events: [event])
        #expect(timeline.contains("userNote"))
        #expect(timeline.contains("remember this"))
    }
}
