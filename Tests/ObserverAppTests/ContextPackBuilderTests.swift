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
            ),
            ObserverEvent(
                type: .writingContext,
                payload: [
                    "app_name": "ChatGPT",
                    "focused_element_value": "Формулирую задачу для Observer",
                    "resource_url": "https://example.com/private?token=secret"
                ],
                workspaceTopologyVersion: 1
            )
        ]

        let pack = ContextPackBuilder(topology: .defaultTwoDisplaySetup).build(events: events, mode: .observing)

        #expect(pack.contains("## Attention Signal"))
        #expect(pack.contains("## Active Writing Context"))
        #expect(!pack.contains("Формулирую задачу"))
        #expect(!pack.contains("example.com/private"))
        #expect(pack.contains("raw writing stays local"))
        #expect(pack.contains("Face: present"))
        #expect(pack.contains("Privacy Notes"))
    }
}
