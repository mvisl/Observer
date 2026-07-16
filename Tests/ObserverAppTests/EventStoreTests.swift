import Foundation
import Testing
@testable import ObserverApp

struct EventStoreTests {
    @Test func redactsPayloadBeforeStorage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("observer-store-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = try EventStore(directory: directory)
        try store.append(
            ObserverEvent(
                type: .screenContext,
                payload: ["selected_text": "password: hunter2"],
                workspaceTopologyVersion: 1
            )
        )

        let event = try #require(store.recentEvents(limit: 1).first)
        #expect(event.payload["selected_text"]?.contains("hunter2") == false)
    }

    @Test func archivesLegacyActivityInsightEventsOnOpen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("observer-store-archive-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        do {
            let store = try EventStore(directory: directory)
            try store.append(
                ObserverEvent(
                    type: .activityInsight,
                    payload: ["insight": "Диалог с ИИ: читает"],
                    workspaceTopologyVersion: 1
                )
            )
            try store.append(
                ObserverEvent(
                    type: .contentContext,
                    payload: ["topic": "real context"],
                    workspaceTopologyVersion: 1
                )
            )
        }

        let reopened = try EventStore(directory: directory)
        let events = try reopened.allEvents()
        #expect(events.contains { $0.type == .activityInsight } == false)
        #expect(events.contains { $0.type == .contentContext } == true)
        #expect(try reopened.archivedActivityInsightCount() == 1)
    }

    @Test func contentKindsRespectRawStoragePolicy() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("observer-store-contract-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try EventStore(directory: directory)
        for kind in ["message", "email", "feed", "prompt", "code", "doc"] {
            try store.append(
                ObserverEvent(
                    type: .contentContext,
                    payload: ["content_kind": kind, "raw_fragment": "private text \(kind)"],
                    workspaceTopologyVersion: 1
                )
            )
        }
        let byKind = Dictionary(uniqueKeysWithValues: try store.allEvents().compactMap { event in
            event.payload["content_kind"].map { ($0, event) }
        })
        #expect(byKind["message"]?.payload["raw_fragment"] == nil)
        #expect(byKind["email"]?.payload["raw_fragment"] == nil)
        #expect(byKind["feed"]?.payload["raw_fragment"] == nil)
        #expect(byKind["prompt"]?.payload["raw_fragment"] == "private text prompt")
        #expect(byKind["code"]?.payload["raw_fragment"] == "private text code")
        #expect(byKind["doc"]?.payload["raw_fragment"] == "private text doc")
    }

    @Test func evidenceFreeCandidateIsQuarantinedBeforeItReachesEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("observer-store-evidence-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try EventStore(directory: directory)
        try store.append(
            ObserverEvent(type: .causalHypothesis, payload: ["claim": "unsupported"], workspaceTopologyVersion: 1)
        )

        #expect(try store.allEvents().isEmpty)
        #expect(try store.quarantinedContractViolationCount() == 1)
    }

    @Test func deduplicatesRestartedSummaryWithinItsTimeWindow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("observer-store-summary-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try EventStore(directory: directory)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        for _ in 0..<2 {
            try store.append(
                ObserverEvent(
                    id: UUID(),
                    timestamp: timestamp,
                    type: .localSummary,
                    source: "test",
                    platform: "macOS",
                    displayRole: nil,
                    appID: nil,
                    confidence: 1,
                    payload: ["summary_kind": "idle", "summary": "same window"],
                    workspaceTopologyVersion: 1
                )
            )
        }
        #expect(try store.allEvents().filter { $0.type == .localSummary }.count == 1)
    }
}
