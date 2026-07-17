import Foundation
import Testing
@testable import ObserverApp

struct DailyActivityReportBuilderTests {
    @Test func reportsAssignedUnassignedAndDoesNotCreateActions() {
        let now = Date()
        let assignedThread = event(.activityThread, at: now, confidence: 0.8, payload: [
            "activity_thread_id": "thread-a",
            "generated_name": "Observer — context fabric",
            "confidence": "0.80",
            "source_event_ids": UUID().uuidString
        ])
        let assignedSlice = event(.contextSlice, at: now.addingTimeInterval(60), confidence: 0.8, payload: [
            "activity_thread_id": "thread-a",
            "assignment_state": "assigned",
            "activity_kind": "ai_assisted",
            "started_at": ISO8601DateFormatter().string(from: now),
            "ended_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(600)),
            "active_seconds": "600",
            "source_event_ids": assignedThread.id.uuidString
        ])
        let unassignedSlice = event(.contextSlice, at: now.addingTimeInterval(700), confidence: 0.3, payload: [
            "activity_thread_id": "",
            "assignment_state": "unassigned",
            "activity_kind": "unknown",
            "started_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(700)),
            "ended_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(1000)),
            "active_seconds": "300",
            "source_event_ids": assignedThread.id.uuidString
        ])

        let result = DailyActivityReportBuilder().build(
            events: [assignedThread, assignedSlice, unassignedSlice],
            day: now
        )

        #expect(result.diagnostics["assigned_active_seconds"] == "600.0")
        #expect(result.diagnostics["unassigned_active_seconds"] == "300.0")
        #expect(result.diagnostics["tracker_actions_enabled"] == "false")
        #expect(result.diagnostics["tracker_external_sending_enabled"] == "false")
        #expect(result.markdown.contains("Observer — context fabric"))
    }

    @Test func replayDatasetContainsRequiredFortyScenariosWithForbiddenAssignments() {
        let fixtures = ContextFabricReplayDataset.fixtures

        #expect(fixtures.count >= 40)
        #expect(Set(fixtures.map(\.id)).count == fixtures.count)
        #expect(fixtures.allSatisfy { !$0.expectedObservations.isEmpty })
        #expect(fixtures.allSatisfy { !$0.forbiddenAssignments.isEmpty })
        #expect(fixtures.contains { $0.name == "same_frame_multiple_cues" })
        #expect(fixtures.contains { $0.name == "idempotent_rebuild" })
    }

    @Test func reportsMeetingsCallsActionItemsAndObjectEvidence() {
        let now = Date()
        let meeting = event(.episode, at: now.addingTimeInterval(60), confidence: 0.8, payload: [
            "episode_kind": "meeting",
            "topic": "weekly onboarding sync",
            "duration_seconds": "1800"
        ])
        let call = event(.episode, at: now.addingTimeInterval(120), confidence: 0.8, payload: [
            "episode_kind": "call",
            "topic": "family logistics",
            "duration_seconds": "900"
        ])
        let item = event(.actionItem, at: now.addingTimeInterval(130), confidence: 0.8, payload: [
            "text": "send onboarding summary",
            "addressee": "me"
        ])
        let object = event(.objectPresence, at: now.addingTimeInterval(140), confidence: 0.8, payload: [
            "object_class": "cell phone",
            "display_eligible": "false"
        ])

        let result = DailyActivityReportBuilder().build(
            events: [meeting, call, item, object],
            day: now
        )

        #expect(result.diagnostics["meeting_episodes"] == "1")
        #expect(result.diagnostics["call_episodes"] == "1")
        #expect(result.diagnostics["action_items"] == "1")
        #expect(result.diagnostics["object_presence"] == "1")
        #expect(result.markdown.contains("Meetings And Calls"))
        #expect(result.markdown.contains("family logistics"))
    }

    @Test func reportsProjectWorkstreamIntentionAttemptAboveApplications() {
        let now = Date()
        let thread = event(.activityThread, at: now, confidence: 0.82, payload: [
            "activity_thread_id": "freelance-obord",
            "generated_name": "Freelance oBoard prototype",
            "confidence": "0.82"
        ])
        let aiEpisode = event(.episode, at: now.addingTimeInterval(10), confidence: 0.8, payload: [
            "episode_kind": "ai_assisted_work",
            "topic": "oBoard prototype generation",
            "apps": "Figma -> ChatGPT -> Codex"
        ])
        let callEpisode = event(.episode, at: now.addingTimeInterval(900), confidence: 0.8, payload: [
            "episode_kind": "call",
            "topic": "oBoard созвон с Витей",
            "apps": "Viber"
        ])
        let aiSlice = event(.contextSlice, at: now.addingTimeInterval(30), confidence: 0.8, payload: [
            "activity_thread_id": "freelance-obord",
            "assignment_state": "assigned",
            "activity_kind": "ai_assisted",
            "episode_event_id": aiEpisode.id.uuidString,
            "started_at": ISO8601DateFormatter().string(from: now),
            "ended_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(600)),
            "active_seconds": "600"
        ])
        let callSlice = event(.contextSlice, at: now.addingTimeInterval(930), confidence: 0.8, payload: [
            "activity_thread_id": "freelance-obord",
            "assignment_state": "assigned",
            "activity_kind": "communication",
            "episode_event_id": callEpisode.id.uuidString,
            "started_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(900)),
            "ended_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(1200)),
            "active_seconds": "300"
        ])

        let result = DailyActivityReportBuilder().build(
            events: [thread, aiEpisode, callEpisode, aiSlice, callSlice],
            day: now
        )

        #expect(result.markdown.contains("## Проекты и намерения"))
        #expect(result.markdown.contains("### Oboard"))
        #expect(result.markdown.contains("#### Dashboard"))
        #expect(result.markdown.contains("##### Улучшение Dashboard"))
        #expect(result.markdown.contains("Попытка подключить Codex к Figma"))
        #expect(result.markdown.contains("Обсуждение текущего решения"))
        #expect(result.markdown.contains("Приложения: ChatGPT → Codex → Figma"))
        #expect(result.markdown.contains("Приложения: Viber"))
        #expect(result.markdown.contains("## Пользовательское время"))
        #expect(result.markdown.contains("## Делегированная агентская работа"))
        #expect(result.markdown.contains("## Хронология намерений"))
        #expect(!result.markdown.contains("## Task Breakdown"))
    }

    @Test func jiraAnchorTakesPriorityAndKeepsLocalTaskResources() {
        let now = Date()
        let episode = event(.episode, at: now, confidence: 0.9, payload: [
            "episode_kind": "design_work",
            "topic": "WhatToBuy dividend card",
            "apps": "Figma -> Google Chrome"
        ])
        let slice = event(.contextSlice, at: now, confidence: 0.9, payload: [
            "activity_thread_id": "",
            "assignment_state": "assigned",
            "activity_kind": "design",
            "episode_event_id": episode.id.uuidString,
            "started_at": ISO8601DateFormatter().string(from: now),
            "ended_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(600)),
            "active_seconds": "600"
        ])
        let jira = event(.artifactIdentity, at: now.addingTimeInterval(5), confidence: 0.95, payload: [
            "kind": "jira_issue",
            "canonical_key": "jira:PD-43661",
            "display_name": "[PD-43661] Deposit page redesign",
            "resource_url": "https://jira.fxclub.org/browse/PD-43661"
        ])
        let figma = event(.artifactIdentity, at: now.addingTimeInterval(10), confidence: 0.9, payload: [
            "kind": "figma_file",
            "canonical_key": "figma:deposit-page",
            "display_name": "Deposit page Figma",
            "resource_url": "https://www.figma.com/design/example/deposit"
        ])

        let result = DailyActivityReportBuilder().build(events: [episode, slice, jira, figma], day: now)

        #expect(result.markdown.contains("### Work"))
        #expect(result.markdown.contains("#### Libertex"))
        #expect(result.markdown.contains("PD-43661 — Deposit page redesign"))
        #expect(result.markdown.contains("Jira: [PD-43661] Deposit page redesign"))
        #expect(result.markdown.contains("Figma: Deposit page Figma"))
    }

    private func event(
        _ type: ObserverEventType,
        at date: Date,
        confidence: Double,
        payload: [String: String]
    ) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: date,
            type: type,
            source: "test",
            platform: "macOS",
            displayRole: nil,
            appID: nil,
            confidence: confidence,
            payload: payload,
            workspaceTopologyVersion: 1
        )
    }
}
