import Foundation
import Testing
@testable import ObserverApp

struct ArchitectureV2FoundationTests {
    @Test func contextSliceSeparatesUserAndAgentTime() {
        let now = Date()
        let slice = ContextSlice(
            id: UUID(),
            startedAt: now,
            endedAt: now.addingTimeInterval(600),
            elapsedSeconds: 600,
            observedSeconds: 600,
            userActiveSeconds: 120,
            userSupervisingSeconds: 90,
            delegatedForegroundSeconds: 240,
            delegatedBackgroundSeconds: 360,
            episodeId: UUID(),
            intervalEpochId: UUID(),
            projectId: UUID(),
            workstreamId: UUID(),
            intentionId: UUID(),
            attemptId: UUID(),
            primaryActor: .codex,
            contributingActors: [.user, .codex],
            engagementMode: .supervising,
            activityKind: .aiAssisted,
            artifactIds: [UUID()],
            intentionAnchorIds: [UUID()],
            evidenceIds: [UUID()],
            attentionShare: 0.4,
            userInputShare: 0.2,
            autonomousChangeScore: 0.8,
            intentionConfidence: 0.7,
            agencyConfidence: 0.8,
            coverage: 0.9,
            pipelineVersion: ArchitectureV2.pipelineVersion
        )

        #expect(slice.userUniqueSeconds == 210)
        #expect(slice.agentExecutionSeconds == 600)
        #expect(ArchitectureV2Invariant.userTimeDoesNotDoubleCount([slice]))
    }

    @Test func intervalEpochRejectsPhantomDurations() {
        let now = Date()
        let epoch = IntervalEpoch(
            id: UUID(),
            processRunId: UUID(),
            processId: 123,
            calendarDate: "2026-07-16",
            timezoneIdentifier: "Europe/Belgrade",
            lockSessionId: nil,
            observationWindowId: UUID(),
            startedAt: now,
            endedAt: now.addingTimeInterval(2 * 60 * 60),
            startReason: .appLaunch,
            endReason: .gracefulTermination,
            pipelineVersion: ArchitectureV2.pipelineVersion
        )

        #expect(epoch.acceptsFocusInterval(start: now.addingTimeInterval(60), end: now.addingTimeInterval(600)))
        #expect(!epoch.acceptsFocusInterval(start: now.addingTimeInterval(60), end: now.addingTimeInterval(19 * 60 * 60)))
        #expect(!epoch.acceptsFocusInterval(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60)))
    }

    @Test func predictionLogSchemaExistsButIsNotShownByDefault() {
        let log = PredictionLog(
            id: UUID(),
            capability: "next_intent",
            modelVersion: "not-active",
            timestamp: Date(),
            workNodeId: nil,
            evidenceIds: [UUID()],
            predictedOutcome: "not_used",
            predictedProbability: 0.0,
            readinessStage: .s0Collect,
            shown: false,
            actualOutcome: nil,
            userFeedback: nil,
            regret: nil,
            createdAt: Date()
        )

        #expect(log.readinessStage == .s0Collect)
        #expect(log.shown == false)
        #expect(ArchitectureV2Invariant.allInterpretationsHaveEvidence(log.evidenceIds))
    }

    @Test func artifactIdentityKeepsJiraAsStableTaskAnchor() {
        let evidence = UUID()
        let jira = ArtifactIdentity(
            id: UUID(),
            kind: .jiraIssue,
            canonicalKey: "jira:PD-43661",
            displayName: "[PD-43661] Deposit page redesign",
            aliases: ["Deposit page", "Andrey feedback"],
            url: "https://jira.fxclub.org/browse/PD-43661",
            providerId: "PD-43661",
            confidence: 0.98,
            sourceEvidenceIds: [evidence],
            pipelineVersion: ArchitectureV2.pipelineVersion
        )

        #expect(jira.kind == .jiraIssue)
        #expect(jira.canonicalKey == "jira:PD-43661")
        #expect(jira.aliases.contains("Andrey feedback"))
        #expect(ArchitectureV2Invariant.allInterpretationsHaveEvidence(jira.sourceEvidenceIds))
    }
}
