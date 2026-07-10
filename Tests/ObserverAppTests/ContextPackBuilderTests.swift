import Testing
@testable import ObserverApp

struct ContextPackBuilderTests {
    @Test func includesPrivacyAndAttentionSections() {
        let events = [
            ObserverEvent(
                type: .appFocus,
                appID: "com.example.app",
                payload: [
                    "app_name": "Example",
                    "content_allowed": "false"
                ],
                workspaceTopologyVersion: 1
            ),
            ObserverEvent(
                type: .attention,
                payload: [
                    "face_present": "true",
                    "attention_zone": "near_camera",
                    "face_position": "center",
                    "face_count": "1"
                ],
                workspaceTopologyVersion: 1
            )
        ]

        let pack = ContextPackBuilder(topology: .defaultTwoDisplaySetup).build(events: events, mode: .observing)

        #expect(pack.contains("## Attention Signal"))
        #expect(pack.contains("Face: present"))
        #expect(pack.contains("Privacy Notes"))
    }
}
