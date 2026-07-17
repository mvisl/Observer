import Foundation

enum DashboardContract {
    static let schemaVersion = "dashboard.v0"
    static let apiVersion = "v1"
}

struct DayDashboardSnapshot: Codable {
    let schemaVersion: String
    let snapshotId: String
    let generatedAt: Date
    let date: String
    let timezone: String
    let pipelineVersion: String
    let dataRevision: String
    let valid: Bool
    let invariantErrors: [String]
    let totals: DashboardTotals
    let confidenceDistribution: DashboardConfidenceDistribution
    let timelineSegments: [DashboardTimelineSegment]
    let threadSummaries: [DashboardThreadSummary]
    let reviewSummary: DashboardReviewSummary
    let sensorSummary: DashboardSensorSummary
    let causalSummary: DashboardCausalSummary
    let readinessSummary: DashboardReadinessSummary
}

struct DashboardTotals: Codable {
    let observedSeconds: Double
    let activeSeconds: Double
    let attributableSeconds: Double
    let assignedSeconds: Double
    let unassignedSeconds: Double
    let idleSeconds: Double
    let sensorGapSeconds: Double
    let coverage: Double
}

struct DashboardConfidenceDistribution: Codable {
    let high: Int
    let medium: Int
    let low: Int
}

struct DashboardTimelineSegment: Codable, Identifiable {
    let id: String
    let start: Date
    let end: Date
    let activeSeconds: Double
    let elapsedSeconds: Double
    let userAttributableSeconds: Double
    let agentExecutionSeconds: Double
    let primaryActor: String
    let engagementMode: String
    let agencyConfidence: Double
    let threadId: String?
    let threadName: String
    let episodeId: String?
    let summary: String
    let applications: [String]
    let artifact: String?
    let activityKind: String
    let confidence: Double
    let evidenceChannels: [String]
    let state: String
    let sourceEventIds: [String]
}

struct DashboardThreadSummary: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let activeSeconds: Double
    let firstSeen: Date?
    let lastSeen: Date?
    let episodes: Int
    let artifacts: [String]
    let applications: [String]
    let confidence: Double
    let hasConflicts: Bool
    let sourceEventIds: [String]
}

struct DashboardReviewSummary: Codable {
    let total: Int
    let unassigned: Int
    let lowConfidence: Int
    let conflictingEvidence: Int
    let sensorGaps: Int
    let items: [DashboardReviewItem]
}

struct DashboardReviewItem: Codable, Identifiable {
    let id: String
    let type: String
    let segmentId: String?
    let title: String
    let affectedSeconds: Double
    let confidence: Double
    let supportingEvidence: [String]
    let contradictingEvidence: [String]
    let alternatives: [String]
    let sourceEventIds: [String]
}

struct DashboardSensorSummary: Codable {
    let channels: [DashboardSensorChannel]
}

struct DashboardSensorChannel: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let coverage: Double
    let freshnessSeconds: Double?
    let events: Int
    let lastEventAt: Date?
}

struct DashboardCausalSummary: Codable {
    let hypotheses: [DashboardCausalHypothesis]
    let episodeChains: [DashboardEpisodeChain]
}

struct DashboardCausalHypothesis: Codable, Identifiable {
    let id: String
    let transition: String
    let mechanism: String
    let maturity: String
    let confidence: Double
    let evidenceEventIds: [String]
}

struct DashboardEpisodeChain: Codable, Identifiable {
    let id: String
    let fromEpisodeId: String
    let toEpisodeId: String
    let kind: String
    let confidence: Double
    let evidenceEventIds: [String]
}

struct DashboardReadinessSummary: Codable {
    let status: String
    let blockers: [String]
    let metrics: [String: String]
}

struct DashboardCorrectionResponse: Codable {
    let accepted: Bool
    let commandId: String
    let dataRevision: String
    let message: String
}
