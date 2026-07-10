import Testing
@testable import ObserverApp

struct ResearchDigestBuilderTests {
    @Test func includesNotesAndHints() {
        let events = [
            ObserverEvent(
                type: .userNote,
                payload: ["note": "test note"],
                workspaceTopologyVersion: 1
            ),
            ObserverEvent(
                type: .hintCandidate,
                payload: ["hint": "quiet hint"],
                workspaceTopologyVersion: 1
            )
        ]

        let digest = ResearchDigestBuilder().build(events: events)
        #expect(digest.contains("test note"))
        #expect(digest.contains("quiet hint"))
        #expect(digest.contains("Next Investigation"))
    }
}
