import Foundation
import Testing
@testable import ObserverApp

struct ContextFabricBuilderTests {
    @Test func normalizesLowConfidenceCameraEvidenceWithoutPublishingTruth() {
        let attention = event(
            .attention,
            confidence: 0.31,
            payload: [
                "face_present": "true",
                "eye_contact_candidate": "true",
                "calibration_version": "camera-attention-v3"
            ]
        )

        let evidence = ContextFabricBuilder().cameraEvidencePayloads(from: attention, now: attention.timestamp.addingTimeInterval(2))

        #expect(evidence.contains { $0["label"] == "user_present" })
        #expect(evidence.contains { $0["label"] == "screen_attention_candidate" && $0["candidate"] == "true" })
        #expect(evidence.allSatisfy { $0["source_event_ids"] == attention.id.uuidString })
    }

    @Test func sameApplicationCanBecomeDifferentThreadsWhenTopicsDiffer() {
        let now = Date()
        let first = episode(
            at: now,
            topic: "observer causal layer",
            apps: "ChatGPT",
            trace: []
        )
        let second = episode(
            at: now.addingTimeInterval(900),
            topic: "personal stroller issue",
            apps: "ChatGPT",
            trace: []
        )

        let result = ContextFabricBuilder().build(events: [first, second], now: now.addingTimeInterval(1200))

        let assignedThreadIDs = Set(result.assignments.compactMap { $0["activity_thread_id"] }.filter { !$0.isEmpty })
        #expect(assignedThreadIDs.count == 2)
        #expect(result.assignments.allSatisfy { $0["reason_codes"]?.contains("same_topic") == true })
    }

    @Test func crossAppEpisodeStaysOneThreadAndSlice() {
        let now = Date()
        let focusA = event(.appFocus, at: now, payload: ["app_name": "Figma"])
        let focusB = event(.appFocus, at: now.addingTimeInterval(60), payload: ["app_name": "ChatGPT"])
        let content = event(.contentContext, at: now.addingTimeInterval(80), payload: ["topic": "Libertex Buy Hold", "content_kind": "prompt"])
        let episode = episode(
            at: now,
            topic: "Libertex Buy Hold",
            apps: "Figma -> ChatGPT -> Codex",
            trace: [focusA, focusB, content]
        )

        let result = ContextFabricBuilder().build(events: [focusA, focusB, content, episode], now: now.addingTimeInterval(900))

        #expect(result.assignments.count == 1)
        #expect(result.contextSlices.count == 1)
        #expect(result.assignments.first?["assignment_state"] == "assigned")
        #expect(result.contextSlices.first?["activity_kind"] == "ai_assisted")
    }

    @Test func idleBreakpointReducesActiveTime() {
        let now = Date()
        let idle = event(.breakpoint, at: now.addingTimeInterval(120), payload: ["reason": "input_pause", "seconds_since_any_input": "90"])
        let episode = episode(
            at: now,
            duration: 300,
            topic: "observer context fabric",
            apps: "ChatGPT",
            trace: [idle]
        )

        let result = ContextFabricBuilder().build(events: [idle, episode], now: now.addingTimeInterval(400))

        #expect(result.contextSlices.first?["elapsed_seconds"] == "300.0")
        #expect(result.contextSlices.first?["active_seconds"] == "210.0")
    }

    @Test func linksOpenedArtifactBackToPriorCommunication() {
        let now = Date()
        let message = event(.contentContext, at: now, payload: [
            "app_name": "Telegram",
            "content_kind": "message",
            "source_entity_display_name": "Andrey",
            "topic": "PD-4366 deposit page redesign"
        ])
        let openedIssue = event(.screenContext, at: now.addingTimeInterval(120), payload: [
            "app_name": "Google Chrome",
            "window_title": "[M] Deposit page redesign [PD-4366] - Jira",
            "url_host": "jira.fxclub.org",
            "url_path": "/browse/PD-4366"
        ])
        let episode = episode(
            at: now,
            topic: "deposit page redesign from Andrey",
            apps: "Telegram -> Google Chrome",
            trace: [message, openedIssue]
        )

        let result = ContextFabricBuilder().build(events: [message, openedIssue, episode], now: now.addingTimeInterval(600))

        #expect(result.artifactTransitions.count == 1)
        #expect(result.artifactTransitions.first?["to_artifact_kind"] == "jira_issue")
        #expect(result.artifactTransitions.first?["shared_identifier"] == "PD-4366")
        #expect(result.artifactTransitions.first?["reason_codes"]?.contains("shared_artifact_identifier") == true)
        #expect(result.artifactTransitions.first?["from_event_id"] == message.id.uuidString)
        #expect(result.artifactTransitions.first?["to_event_id"] == openedIssue.id.uuidString)
    }

    @Test func redactsSecretsFromArtifactLabelsAndKeys() {
        let now = Date()
        let message = event(.contentContext, at: now, payload: [
            "app_name": "Telegram",
            "content_kind": "message",
            "source_entity_display_name": "Andrey",
            "topic": "PD-4366 password: hunter2 deposit redesign"
        ])
        let openedIssue = event(.screenContext, at: now.addingTimeInterval(60), payload: [
            "app_name": "Google Chrome",
            "window_title": "PD-4366 password: hunter2 deposit redesign",
            "url_host": "jira.fxclub.org"
        ])
        let episode = episode(
            at: now,
            topic: "deposit page redesign",
            apps: "Telegram -> Google Chrome",
            trace: [message, openedIssue]
        )

        let result = ContextFabricBuilder().build(events: [message, openedIssue, episode], now: now.addingTimeInterval(600))

        let artifactText = result.artifactIdentities.map { "\($0["display_name"] ?? "") \($0["canonical_key"] ?? "")" }.joined(separator: " ")
        let transitionText = result.artifactTransitions.map { "\($0["artifact_label"] ?? "") \($0["source_context_label"] ?? "")" }.joined(separator: " ")
        #expect(!artifactText.contains("hunter2"))
        #expect(!transitionText.contains("hunter2"))
        #expect(artifactText.contains("[secret]"))
    }

    private func episode(
        at date: Date,
        duration: TimeInterval = 600,
        topic: String,
        apps: String,
        trace: [ObserverEvent]
    ) -> ObserverEvent {
        let iso = ISO8601DateFormatter()
        let traceIDs = trace.map(\.id.uuidString).joined(separator: ",")
        return event(
            .episode,
            at: date.addingTimeInterval(duration),
            confidence: 0.75,
            payload: [
                "episode_id": UUID().uuidString,
                "episode_kind": apps.lowercased().contains("chatgpt") ? "ai_assisted_work" : "mixed",
                "topic": topic,
                "goal": topic,
                "start": iso.string(from: date),
                "end": iso.string(from: date.addingTimeInterval(duration)),
                "apps": apps,
                "trace_event_ids": traceIDs,
                "source_event_ids": traceIDs
            ]
        )
    }

    private func event(
        _ type: ObserverEventType,
        at date: Date = Date(),
        confidence: Double = 0.8,
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
