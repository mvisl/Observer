import Foundation

enum ObserverEventType: String, Codable {
    case appLaunch
    case appShutdown
    case activityInsight
    case attention
    case appFocus
    case appFocusInterval
    case attentionSpan
    case awayPresenceIncident
    case behaviorCue
    case boundReaction
    case breakpoint
    case cameraAttentionStarted
    case cameraAttentionStopped
    case cameraPermission
    case cognitiveState
    case detectorFired
    case displayInventory
    case episode
    case experiment
    case hintCandidate
    case inputActivity
    case typingRhythm
    case mouseDynamics
    case scrollProfile
    case clipboardRoute
    case comparisonLayoutCandidate
    case externalLLMRequest
    case fusionHypothesis
    case geminiInsight
    case geminiKeyDeleted
    case geminiKeyUpdated
    case gazeCalibrationSample
    case localInsight
    case mediaPlayback
    case mediaReaction
    case personalBaseline
    case prediction
    case predictorCalibration
    case researchDigest
    case resumptionLag
    case scheduleOverride
    case securityIncident
    case sequencePattern
    case localSummary
    case ocrContext
    case screenContext
    case sessionBoundary
    case observingStarted
    case observingPaused
    case observationGap
    case contextPackGenerated
    case contentContext
    case privacyAllowlistAdded
    case privacyExclusionAdded
    case userNote
    case userLabel
    case writingContext
    case workspaceTopologyLoaded
    case weeklyReport
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
