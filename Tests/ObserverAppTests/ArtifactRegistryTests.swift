import Foundation
import Testing
@testable import ObserverApp

@Suite("ArtifactRegistryTests")
struct ArtifactRegistryTests {
    @Test
    func mergesAliasesAndKeepsOneCanonicalArtifact() {
        let now = Date()
        let first = event(at: now, payload: [
            "canonical_key": "jira:PD-6455",
            "kind": "jira_issue",
            "display_name": "PD-6455",
            "resource_url": "https://jira.example/browse/PD-6455",
            "source_event_ids": "source-a"
        ])
        let second = event(at: now.addingTimeInterval(60), payload: [
            "canonical_key": "jira:PD-6455",
            "kind": "jira_issue",
            "display_name": "PD-6455 Contextual bottom navigation",
            "source_event_ids": "source-b"
        ])

        let entries = ArtifactRegistry().entries(from: [first, second])

        #expect(entries.count == 1)
        #expect(entries[0].title == "PD-6455 Contextual bottom navigation")
        #expect(entries[0].aliases.contains("PD-6455"))
        #expect(entries[0].evidenceEventIds.contains("source-a"))
        #expect(entries[0].evidenceEventIds.contains("source-b"))
    }

    @Test
    func assignsSemanticRolesInsteadOfAnAppList() {
        let now = Date()
        let threadID = "thread-1"
        let jira = event(at: now, payload: [
            "canonical_key": "jira:PD-6455", "kind": "jira_issue", "display_name": "PD-6455", "source_event_ids": "source-jira"
        ])
        let figma = event(at: now, payload: [
            "canonical_key": "figma:file-1", "kind": "figma_file", "display_name": "WhatToBuy file", "source_event_ids": "source-figma"
        ])
        let thread = ObserverEvent(type: .activityThread, source: "test", confidence: 1, payload: [
            "activity_thread_id": threadID, "source_event_ids": "source-jira,source-figma"
        ], workspaceTopologyVersion: 1)
        let segment = DashboardTimelineSegment(
            id: "slice-1", start: now, end: now.addingTimeInterval(60), activeSeconds: 60, elapsedSeconds: 60,
            userAttributableSeconds: 60, agentExecutionSeconds: 0, primaryActor: "user", engagementMode: "active",
            agencyConfidence: 1, threadId: threadID, threadName: "Task", episodeId: "episode-1", summary: "Work",
            applications: [], artifact: nil, activityKind: "design", confidence: 1, evidenceChannels: [], state: "assigned",
            sourceEventIds: ["source-jira", "source-figma"]
        )

        let relations = DashboardArtifactInspectorBuilder().build(artifacts: [jira, figma], threads: [thread], segments: [segment])

        #expect(relations.map(\.role) == [.primaryArtifact, .currentResult])
        #expect(relations.allSatisfy { $0.relatedEpisodeCount == 1 })
    }

    @Test
    func keepsLocalArtifactCorrectionsAcrossSnapshotRebuilds() {
        let now = Date()
        let threadID = "thread-1"
        let jira = event(at: now, payload: [
            "canonical_key": "jira:PD-6455", "kind": "jira_issue", "display_name": "PD-6455", "source_event_ids": "source-jira"
        ])
        let thread = ObserverEvent(type: .activityThread, source: "test", confidence: 1, payload: [
            "activity_thread_id": threadID, "source_event_ids": "source-jira"
        ], workspaceTopologyVersion: 1)
        let segment = DashboardTimelineSegment(
            id: "slice-1", start: now, end: now.addingTimeInterval(60), activeSeconds: 60, elapsedSeconds: 60,
            userAttributableSeconds: 60, agentExecutionSeconds: 0, primaryActor: "user", engagementMode: "active",
            agencyConfidence: 1, threadId: threadID, threadName: "Task", episodeId: "episode-1", summary: "Work",
            applications: [], artifact: nil, activityKind: "design", confidence: 1, evidenceChannels: [], state: "assigned",
            sourceEventIds: ["source-jira"]
        )
        let rename = ObserverEvent(type: .contextLinkUserLabel, source: "dashboard_api", confidence: 1, payload: [
            "command_type": "artifact_rename", "artifact_id": "thread-1:jira:PD-6455", "title": "Bottom navigation decision"
        ], workspaceTopologyVersion: 1)

        let relations = DashboardArtifactInspectorBuilder().build(
            artifacts: [jira], threads: [thread], segments: [segment], corrections: [rename]
        )

        #expect(relations.map(\.title) == ["Bottom navigation decision"])
    }

    private func event(at date: Date, payload: [String: String]) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: date,
            type: .artifactIdentity,
            source: "test",
            platform: "macOS",
            displayRole: nil,
            appID: nil,
            confidence: 0.9,
            payload: payload,
            workspaceTopologyVersion: 1
        )
    }
}
