import Foundation
import Testing
@testable import ObserverApp

struct IntentionAttributionBuilderTests {
    @Test func promptAnchorAssignsNearbyAndPropagatesToRelatedSpan() {
        let now = Date()
        let prompt = event(.contentContext, at: now, payload: [
            "content_kind": "prompt",
            "topic": "WhatToBuy dividend card hierarchy",
            "raw_fragment": "Turn WhatToBuy dividend cards into clear teaser-level product signals"
        ])
        let direct = span(at: now.addingTimeInterval(5 * 60), apps: "ChatGPT -> Figma")
        let bridge = span(at: now.addingTimeInterval(15 * 60), apps: "Figma -> Google Chrome")
        let propagated = span(at: now.addingTimeInterval(25 * 60), apps: "Google Chrome -> Figma")

        let result = IntentionAttributionBuilder().build(events: [prompt, direct, bridge, propagated])

        #expect(result.anchors.count == 1)
        #expect(result.spanAssignments.contains { $0["assigned_by"] == "prompt_anchor" })
        #expect(result.spanAssignments.contains { $0["assigned_by"] == "propagation" })
        #expect(result.spanAssignments.allSatisfy { $0["intent_phrase"]?.isEmpty == false })
    }

    private func span(at start: Date, apps: String) -> ObserverEvent {
        let iso = ISO8601DateFormatter()
        return event(.attentionSpan, at: start.addingTimeInterval(5 * 60), payload: [
            "start": iso.string(from: start),
            "end": iso.string(from: start.addingTimeInterval(5 * 60)),
            "apps": apps
        ])
    }

    private func event(_ type: ObserverEventType, at date: Date, payload: [String: String]) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: date,
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
