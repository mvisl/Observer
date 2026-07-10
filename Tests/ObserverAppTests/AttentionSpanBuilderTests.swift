import Foundation
import Testing
@testable import ObserverApp

struct AttentionSpanBuilderTests {
    @Test func clustersFastSwitchesIntoOneAISpan() {
        let start = Date(timeIntervalSince1970: 1_000)
        let events = [
            focus("ChatGPT", at: start),
            focus("Google Chrome", at: start.addingTimeInterval(30)),
            focus("Figma", at: start.addingTimeInterval(70))
        ]

        let span = AttentionSpanBuilder().build(from: events, now: start.addingTimeInterval(100))

        #expect(span?.payload["span_kind"] == "ai_assisted_design")
        #expect(span?.payload["apps"] == "ChatGPT -> Google Chrome -> Figma")
        #expect(span?.payload["switches_within_span"] == "2")
    }

    @Test func breaksSpanWhenGapIsLong() {
        let start = Date(timeIntervalSince1970: 1_000)
        let events = [
            focus("ChatGPT", at: start),
            focus("Google Chrome", at: start.addingTimeInterval(95)),
            focus("Claude", at: start.addingTimeInterval(120))
        ]

        let span = AttentionSpanBuilder().build(from: events, now: start.addingTimeInterval(130))

        #expect(span?.payload["apps"] == "Google Chrome -> Claude")
        #expect(span?.payload["switches_within_span"] == "1")
    }

    private func focus(_ appName: String, at date: Date) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: date,
            type: .appFocus,
            source: "test",
            platform: "macOS",
            displayRole: nil,
            appID: appName.lowercased().replacingOccurrences(of: " ", with: "."),
            confidence: 1,
            payload: ["app_name": appName],
            workspaceTopologyVersion: 1
        )
    }
}
