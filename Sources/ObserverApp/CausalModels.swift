import Foundation

enum EpisodeStatus: String, Codable {
    case open
    case provisional
    case closed
    case revised
}

enum EpisodeStage: String, Codable {
    case starting
    case exploring
    case executing
    case reviewing
    case correcting
    case blocked
    case resolving
    case completed
    case abandoned
    case unknown
}

enum TransitionType: String, Codable {
    case taskStarted = "task_started"
    case goalChanged = "goal_changed"
    case topicChanged = "topic_changed"
    case frictionDetected = "friction_detected"
    case correctionLoopStarted = "correction_loop_started"
    case correctionLoopRepeated = "correction_loop_repeated"
    case blocked
    case unblocked
    case taskInterrupted = "task_interrupted"
    case taskResumed = "task_resumed"
    case taskAbandoned = "task_abandoned"
    case taskCompleted = "task_completed"
    case emotionalToneShift = "emotional_tone_shift"
    case unknownChange = "unknown_change"
}

enum CausalRole: String, Codable {
    case trigger
    case enablingCondition = "enabling_condition"
    case maintainingFactor = "maintaining_factor"
    case blocker
    case resolution
    case consequence
    case unknown
}

enum CausalMaturityLevel: String, Codable {
    case sequence
    case association
    case plausibleMechanism = "plausible_mechanism"
    case repeatedPattern = "repeated_pattern"
    case counterfactualSupport = "counterfactual_support"
}

enum CausalHypothesisStatus: String, Codable {
    case candidate
    case supported
    case weakened
    case rejected
    case insufficientEvidence = "insufficient_evidence"
}

struct Episode: Codable, Identifiable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var status: EpisodeStatus
    var primaryTask: String?
    var topic: String?
    var goal: String?
    var stage: EpisodeStage?
    var appIds: [String]
    var contentContextIds: [UUID]
    var sourceEventIds: [UUID]
    var confidence: Double
    var createdByPipelineVersion: String
    var lastUpdatedAt: Date
}

struct StateTransition: Codable, Identifiable {
    let id: UUID
    let episodeId: UUID
    let startedAt: Date
    let detectedAt: Date
    let fromState: String
    let toState: String
    let transitionType: TransitionType
    let observableChanges: [String]
    let sourceEventIds: [UUID]
    let confidence: Double
    let pipelineVersion: String
}

struct CausalAntecedent: Codable, Identifiable {
    let id: UUID
    let transitionId: UUID
    let episodeId: UUID
    let description: String
    let role: CausalRole
    let occurredAt: Date?
    let temporalDistanceSeconds: Double?
    let sourceEventIds: [UUID]
    let semanticRelevance: Double
    let temporalRelevance: Double
    let recurrenceScore: Double
}

struct CausalHypothesis: Codable, Identifiable {
    let id: UUID
    let episodeId: UUID
    let transitionId: UUID
    let antecedentId: UUID
    let claim: String
    let mechanism: String
    let supportingEvidenceIds: [UUID]
    let contradictingEvidenceIds: [UUID]
    let alternativeHypothesisIds: [UUID]
    let maturityLevel: CausalMaturityLevel
    let status: CausalHypothesisStatus
    let confidence: Double
    let modelName: String?
    let modelVersion: String?
    let promptVersion: String?
    let pipelineVersion: String
    let createdAt: Date
    let updatedAt: Date
}

struct PersonalCausalPattern: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let mechanism: String
    let supportingEpisodeIds: [UUID]
    let contradictingEpisodeIds: [UUID]
    let contextsWhereObserved: [String]
    let contextsWhereNotObserved: [String]
    let maturityLevel: CausalMaturityLevel
    let confidence: Double
    let firstObservedAt: Date
    let lastValidatedAt: Date
    let pipelineVersion: String
}

struct CausalEvidence: Codable, Identifiable {
    let id: UUID
    let episodeId: UUID
    let channel: String
    let independenceGroup: String
    let proposition: String
    let polarity: String
    let reliability: Double
    let freshness: Double
    let sourceEventIds: [UUID]
}
