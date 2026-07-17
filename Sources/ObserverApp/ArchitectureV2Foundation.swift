import Foundation

enum ArchitectureV2 {
    static let pipelineVersion = "observer-architecture-v2-wave-0"
}

enum ArtifactKind: String, Codable, CaseIterable {
    case jiraIssue = "jira_issue"
    case figmaFile = "figma_file"
    case figmaPage = "figma_page"
    case figmaNode = "figma_node"
    case repository
    case branch
    case sourceFile = "source_file"
    case document
    case spreadsheet
    case browserPage = "browser_page"
    case webApplication = "web_application"
    case aiConversation = "ai_conversation"
    case chatThread = "chat_thread"
    case emailThread = "email_thread"
    case terminalSession = "terminal_session"
    case codexSession = "codex_session"
    case meeting
    case offlineMarker = "offline_marker"
    case unknown
}

enum ArtifactRelationType: String, Codable, CaseIterable {
    case references
    case createdFrom = "created_from"
    case revises
    case discusses
    case implements
    case verifies
    case linkedFrom = "linked_from"
    case sameAs = "same_as"
    case aliasOf = "alias_of"
}

struct ArtifactIdentity: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: ArtifactKind
    let canonicalKey: String
    let displayName: String
    let aliases: [String]
    let url: String?
    let providerId: String?
    let confidence: Double
    let sourceEvidenceIds: [UUID]
    let pipelineVersion: String
}

struct ArtifactRelation: Codable, Equatable, Identifiable {
    let id: UUID
    let fromArtifactId: UUID
    let toArtifactId: UUID
    let relationType: ArtifactRelationType
    let evidenceIds: [UUID]
    let confidence: Double
    let source: String
    let createdAt: Date
    let revision: Int
    let pipelineVersion: String
}

enum IntentionAnchorSourceType: String, Codable, CaseIterable {
    case userPrompt = "user_prompt"
    case userMessage = "user_message"
    case explicitLabel = "explicit_label"
    case taskDescription = "task_description"
    case issueTitle = "issue_title"
    case meetingActionItem = "meeting_action_item"
    case clipboardGoal = "clipboard_goal"
    case manualEntry = "manual_entry"
}

struct IntentionAnchor: Codable, Equatable, Identifiable {
    let id: UUID
    let sourceType: IntentionAnchorSourceType
    let timestamp: Date
    let validFrom: Date
    let validUntil: Date?
    let projectCandidates: [UUID]
    let workstreamCandidates: [UUID]
    let intentionCandidates: [UUID]
    let goalSummary: String
    let expectedOutcome: String?
    let artifactIds: [UUID]
    let entityIds: [UUID]
    let topicIds: [UUID]
    let confidence: Double
    let sourceEvidenceIds: [UUID]
    let pipelineVersion: String
}

enum ActivityKindV2: String, Codable, CaseIterable {
    case design
    case coding
    case research
    case communication
    case aiAssisted = "ai_assisted"
    case meeting
    case media
    case admin
    case unknown
}

struct ContextSlice: Codable, Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let elapsedSeconds: Double
    let observedSeconds: Double
    let userActiveSeconds: Double
    let userSupervisingSeconds: Double
    let delegatedForegroundSeconds: Double
    let delegatedBackgroundSeconds: Double
    let episodeId: UUID?
    let intervalEpochId: UUID
    let projectId: UUID?
    let workstreamId: UUID?
    let intentionId: UUID?
    let attemptId: UUID?
    let primaryActor: WorkActor
    let contributingActors: [WorkActor]
    let engagementMode: EngagementMode
    let activityKind: ActivityKindV2
    let artifactIds: [UUID]
    let intentionAnchorIds: [UUID]
    let evidenceIds: [UUID]
    let attentionShare: Double
    let userInputShare: Double
    let autonomousChangeScore: Double
    let intentionConfidence: Double
    let agencyConfidence: Double
    let coverage: Double
    let pipelineVersion: String

    var userUniqueSeconds: Double {
        min(observedSeconds, userActiveSeconds + userSupervisingSeconds)
    }

    var agentExecutionSeconds: Double {
        delegatedForegroundSeconds + delegatedBackgroundSeconds
    }
}

enum EpochStartReason: String, Codable, CaseIterable {
    case appLaunch = "app_launch"
    case login
    case unlock
    case wake
    case scheduleStart = "schedule_start"
    case dayBoundary = "day_boundary"
    case timezoneBoundary = "timezone_boundary"
    case restartContinuation = "restart_continuation"
}

enum EpochEndReason: String, Codable, CaseIterable {
    case gracefulTermination = "graceful_termination"
    case lock
    case sleep
    case logout
    case scheduleEnd = "schedule_end"
    case dayBoundary = "day_boundary"
    case timezoneBoundary = "timezone_boundary"
    case crashCandidate = "crash_candidate"
    case sanityThreshold = "sanity_threshold"
}

struct IntervalEpoch: Codable, Equatable, Identifiable {
    let id: UUID
    let processRunId: UUID
    let processId: Int
    let calendarDate: String
    let timezoneIdentifier: String
    let lockSessionId: String?
    let observationWindowId: UUID?
    let startedAt: Date
    let endedAt: Date?
    let startReason: EpochStartReason
    let endReason: EpochEndReason?
    let pipelineVersion: String

    func acceptsFocusInterval(start: Date, end: Date, maxDurationHours: Double = 18) -> Bool {
        guard end > start else { return false }
        guard end.timeIntervalSince(start) <= maxDurationHours * 60 * 60 else { return false }
        guard start >= startedAt else { return false }
        if let endedAt {
            return end <= endedAt
        }
        return true
    }
}

enum ShutdownReason: String, Codable, CaseIterable {
    case graceful
    case devRebuild = "dev_rebuild"
    case forcedKill = "forced_kill"
    case crashCandidate = "crash_candidate"
    case systemShutdown = "system_shutdown"
    case unknown
}

struct ProcessRun: Codable, Equatable, Identifiable {
    let id: UUID
    let processId: Int
    let startedAt: Date
    let endedAt: Date?
    let buildId: String
    let commitHash: String?
    let signingIdentityHash: String
    let shutdownReason: ShutdownReason
    let exitCode: Int?
    let gracefulMarkerWritten: Bool
    let crashReportId: String?
    let previousRunId: UUID?
    let nextRunId: UUID?
}

enum CapabilityReadinessStage: String, Codable, CaseIterable {
    case s0Collect = "S0_collect"
    case s1Shadow = "S1_shadow"
    case s2CalibratedShadow = "S2_calibrated_shadow"
    case s3TrustedLimited = "S3_trusted_limited"
    case s4Full = "S4_full"
}

struct PredictionLog: Codable, Equatable, Identifiable {
    let id: UUID
    let capability: String
    let modelVersion: String
    let timestamp: Date
    let workNodeId: UUID?
    let evidenceIds: [UUID]
    let predictedOutcome: String
    let predictedProbability: Double
    let readinessStage: CapabilityReadinessStage
    let shown: Bool
    let actualOutcome: String?
    let userFeedback: String?
    let regret: String?
    let createdAt: Date
}

enum ArchitectureV2Invariant {
    static func userTimeDoesNotDoubleCount(_ slices: [ContextSlice]) -> Bool {
        let totalObserved = slices.reduce(0) { $0 + $1.observedSeconds }
        let totalUser = slices.reduce(0) { $0 + $1.userUniqueSeconds }
        return totalUser <= totalObserved + 0.001
    }

    static func allInterpretationsHaveEvidence(_ evidenceIds: [UUID]) -> Bool {
        !evidenceIds.isEmpty
    }
}
