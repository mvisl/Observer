import Foundation
import Testing
@testable import ObserverApp

struct EpisodeBuilderTests {
    @Test func buildsEpisodeFromAttentionSpans() {
        let start = Date(timeIntervalSince1970: 1_000)
        let events = [
            span(
                kind: "ai_assisted_design",
                apps: "ChatGPT -> Figma",
                switches: 3,
                at: start.addingTimeInterval(120)
            ),
            focus("Google Chrome", at: start.addingTimeInterval(240))
        ]

        let episode = EpisodeBuilder().build(
            events: events,
            start: start,
            end: start.addingTimeInterval(700),
            outcome: "idle_started"
        )

        #expect(episode?.payload["episode_kind"] == "ai_assisted_work")
        #expect(episode?.payload["dominant_context"] == "ai_assisted_design")
        #expect(episode?.payload["apps"] == "ChatGPT -> Figma -> Google Chrome")
        #expect(episode?.payload["switches_within_span"] == "3")
        #expect(episode?.payload["outcome"] == "idle_started")
    }

    @Test func ignoresVeryShortEpisodes() {
        let start = Date(timeIntervalSince1970: 1_000)
        let episode = EpisodeBuilder().build(
            events: [focus("ChatGPT", at: start.addingTimeInterval(10))],
            start: start,
            end: start.addingTimeInterval(30),
            outcome: "focus_changed"
        )

        #expect(episode == nil)
    }

    @Test func buildsMeetingEpisodeFromMeetContext() {
        let start = Date(timeIntervalSince1970: 2_000)
        let events = [
            focus("Google Chrome", at: start.addingTimeInterval(5)),
            event(.contentContext, at: start.addingTimeInterval(30), payload: [
                "content_kind": "meeting_captions",
                "topic": "weekly onboarding sync",
                "participants": "Anna,Denis"
            ])
        ]

        let episode = EpisodeBuilder().build(
            events: events,
            start: start,
            end: start.addingTimeInterval(900),
            outcome: "meeting_ended"
        )

        #expect(episode?.payload["episode_kind"] == "meeting")
        #expect(episode?.payload["topic"] == "weekly onboarding sync")
    }

    @Test func buildsCallEpisodeFromDistilledCallContext() {
        let start = Date(timeIntervalSince1970: 3_000)
        let events = [
            focus("Rakuten Viber", at: start.addingTimeInterval(5)),
            event(.contentContext, at: start.addingTimeInterval(45), payload: [
                "content_kind": "call_distilled",
                "topic": "family logistics",
                "source_entity_display_name": "Mother"
            ])
        ]

        let episode = EpisodeBuilder().build(
            events: events,
            start: start,
            end: start.addingTimeInterval(1_200),
            outcome: "call_ended"
        )

        #expect(episode?.payload["episode_kind"] == "call")
        #expect(episode?.payload["topic"] == "family logistics")
    }

    private func span(kind: String, apps: String, switches: Int, at date: Date) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: date,
            type: .attentionSpan,
            source: "test",
            platform: "macOS",
            displayRole: nil,
            appID: nil,
            confidence: 1,
            payload: [
                "span_kind": kind,
                "apps": apps,
                "switches_within_span": "\(switches)"
            ],
            workspaceTopologyVersion: 1
        )
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

    private func event(_ type: ObserverEventType, at date: Date, payload: [String: String]) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: date,
            type: type,
            source: "test",
            platform: "macOS",
            displayRole: nil,
            appID: nil,
            confidence: 1,
            payload: payload,
            workspaceTopologyVersion: 1
        )
    }
}
