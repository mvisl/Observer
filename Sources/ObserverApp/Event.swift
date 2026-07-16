import Foundation

enum ObserverEventType: String, Codable {
    case appLaunch
    case appShutdown
    case activityInsight
    case attention
    case appFocus
    case appFocusInterval
    case actionItem
    case audioCaptureState
    case attentionSpan
    case awayPresenceIncident
    case behaviorCue
    case boundReaction
    case breakpoint
    case cameraAttentionStarted
    case cameraAttentionStopped
    case cameraCueTrajectory
    case cameraDetectorABReport
    case cameraEvidence
    case cameraPermission
    case cameraTier2Sample
    case causalAntecedent
    case causalHypothesis
    case causalUnderstandingReport
    case causalValidationReport
    case cognitiveState
    case detectorFired
    case displayInventory
    case evidence
    case episode
    case episodeThreadAssignment
    case experiment
    case hintCandidate
    case inputActivity
    case intentionAnchor
    case typingRhythm
    case mouseDynamics
    case scrollProfile
    case clipboardRoute
    case comparisonLayoutCandidate
    case externalLLMRequest
    case fusionAudit
    case fusionHypothesis
    case funnelReport
    case geminiInsight
    case geminiKeyDeleted
    case geminiKeyUpdated
    case gazeCalibrationSample
    case localInsight
    case interventionCandidate
    case interventionDecision
    case interventionOutcome
    case objectPresence
    case mediaPlayback
    case mediaReaction
    case chainLink
    case personalBaseline
    case personalCausalPattern
    case prediction
    case predictorCalibration
    case researchDigest
    case readinessReport
    case resumptionLag
    case scheduleOverride
    case securityIncident
    case sequencePattern
    case spanIntentionAssignment
    case situationModel
    case stateTransition
    case localSummary
    case ocrContext
    case screenContext
    case sessionBoundary
    case observingStarted
    case observingPaused
    case observationGap
    case activityThread
    case artifactIdentity
    case artifactTransition
    case contextPackGenerated
    case contextLinkAudit
    case contextLinkUserLabel
    case contextSlice
    case contentContext
    case privacyAllowlistAdded
    case privacyExclusionAdded
    case userNote
    case userLabel
    case writingContext
    case workspaceTopologyLoaded
    case dailyActivityReport
    case weeklyReport
    case workNode
    case episodeWorkAssignment
    case heartbeat
    case sensorHealth
    case focusIntervalRejected
}

enum ObserverPipeline {
    static let version = "observer-brain-v2-foundation"
}

extension ObserverEventType {
    var requiresLineage: Bool {
        switch self {
        case .activityThread,
             .artifactIdentity,
             .artifactTransition,
             .attentionSpan,
             .behaviorCue,
             .boundReaction,
             .cameraEvidence,
             .cameraCueTrajectory,
             .cameraDetectorABReport,
             .cameraTier2Sample,
             .chainLink,
             .causalAntecedent,
             .causalHypothesis,
             .causalUnderstandingReport,
             .causalValidationReport,
             .cognitiveState,
             .contextLinkAudit,
             .contextLinkUserLabel,
             .contextSlice,
             .dailyActivityReport,
             .detectorFired,
             .episodeThreadAssignment,
             .episode,
             .evidence,
             .fusionAudit,
             .fusionHypothesis,
             .funnelReport,
             .geminiInsight,
             .hintCandidate,
             .intentionAnchor,
             .interventionCandidate,
             .interventionDecision,
             .interventionOutcome,
             .localInsight,
             .localSummary,
             .mediaReaction,
             .objectPresence,
             .personalBaseline,
             .personalCausalPattern,
             .prediction,
             .predictorCalibration,
             .readinessReport,
             .researchDigest,
             .resumptionLag,
             .sequencePattern,
             .spanIntentionAssignment,
             .situationModel,
             .stateTransition,
             .weeklyReport:
            return true
        case .workNode,
             .episodeWorkAssignment:
            return true
        default:
            return false
        }
    }

    var isUserVisibleCandidate: Bool {
        switch self {
        case .geminiInsight, .hintCandidate, .localInsight, .mediaReaction, .situationModel, .interventionCandidate:
            return true
        default:
            return false
        }
    }
}

enum UserVisibleOutputPolicy {
    enum Decision: String {
        case allowed
        case missingLineage
        case lowAbstraction
        case legacyPrimarySource
        case missingEvidence
    }

    static func validate(payload: [String: String]) -> Decision {
        if payload["primary_source_type"] == ObserverEventType.activityInsight.rawValue {
            return .legacyPrimarySource
        }
        guard payload["pipeline_version"]?.isEmpty == false,
              payload["session_id"]?.isEmpty == false,
              payload["episode_id"]?.isEmpty == false
        else {
            return .missingLineage
        }
        let sources = payload["source_event_ids"] ?? payload["evidence_event_ids"] ?? ""
        guard sources.isEmpty == false else {
            return .missingEvidence
        }
        let level = payload["abstraction_level"] ?? payload["insight_level"] ?? ""
        guard ["L2", "L3", "L4"].contains(level) else {
            return .lowAbstraction
        }
        return .allowed
    }
}

struct ObserverEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let type: ObserverEventType
    let source: String
    let platform: String
    let displayRole: WorkspaceTopology.DisplayRole?
    let appID: String?
    let confidence: Double
    let payload: [String: String]
    let workspaceTopologyVersion: Int

    init(
        type: ObserverEventType,
        source: String = "observer_app",
        displayRole: WorkspaceTopology.DisplayRole? = nil,
        appID: String? = nil,
        confidence: Double = 1.0,
        payload: [String: String] = [:],
        workspaceTopologyVersion: Int
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.source = source
        self.platform = "macOS"
        self.displayRole = displayRole
        self.appID = appID
        self.confidence = confidence
        self.payload = payload
        self.workspaceTopologyVersion = workspaceTopologyVersion
    }

    init(
        id: UUID,
        timestamp: Date,
        type: ObserverEventType,
        source: String,
        platform: String,
        displayRole: WorkspaceTopology.DisplayRole?,
        appID: String?,
        confidence: Double,
        payload: [String: String],
        workspaceTopologyVersion: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.source = source
        self.platform = platform
        self.displayRole = displayRole
        self.appID = appID
        self.confidence = confidence
        self.payload = payload
        self.workspaceTopologyVersion = workspaceTopologyVersion
    }
}
