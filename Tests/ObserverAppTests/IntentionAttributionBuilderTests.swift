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

    @Test func doesNotPropagateYesterdayIntentionIntoTodayWithoutFreshAnchor() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 23, minute: 45))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 0, minute: 5))!
        let prompt = event(.contentContext, at: yesterday, payload: [
            "content_kind": "prompt",
            "topic": "Andrey feedback for PD-3748",
            "raw_fragment": "Apply Andrey feedback to PD-3748"
        ])
        let yesterdaySpan = span(at: yesterday.addingTimeInterval(5 * 60), apps: "ChatGPT -> Figma")
        let todaySpan = span(at: today, apps: "Figma -> Google Chrome")

        var builder = IntentionAttributionBuilder()
        builder.calendar = calendar
        let result = builder.build(events: [prompt, yesterdaySpan, todaySpan])

        #expect(result.spanAssignments.count == 1)
        #expect(result.spanAssignments.allSatisfy { $0["attention_span_id"] != todaySpan.id.uuidString })
    }

    @Test func doesNotPropagateAcrossObservationGap() {
        let now = Date()
        let prompt = event(.contentContext, at: now, payload: [
            "content_kind": "prompt",
            "topic": "PD-3748 task",
            "raw_fragment": "Work on PD-3748"
        ])
        let direct = span(at: now.addingTimeInterval(5 * 60), apps: "ChatGPT -> Figma")
        let later = span(at: now.addingTimeInterval(15 * 60), apps: "Figma -> Google Chrome")
        let gap = event(.observationGap, at: now.addingTimeInterval(12 * 60), payload: ["reason": "sleep"])

        let result = IntentionAttributionBuilder().build(events: [prompt, direct, gap, later])

        #expect(result.spanAssignments.count == 1)
        #expect(result.spanAssignments.allSatisfy { $0["attention_span_id"] != later.id.uuidString })
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
