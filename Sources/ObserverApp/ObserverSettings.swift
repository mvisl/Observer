import Foundation

struct ObserverSettings: Codable {
    struct DetectorSettings: Codable {
        var frequentSwitchFocusEvents: Int
        var frequentSwitchUniqueApps: Int
        var returnLoopMinimumEvents: Int
        var returnLoopMinimumReturns: Int
        var readingPauseSeconds: Double
    }

    struct CameraDetectorSettings: Codable {
        var tier2SidecarEnabled: Bool
        var tier2SocketPath: String
        var tier2BackgroundFPS: Double
        var tier2BatteryFPS: Double
        var tier2BurstSeconds: Double
        var tier2BurstPrePostSeconds: Double
        var tier1SmileCandidateThreshold: Double
        var tier1MouthOpenCandidateThreshold: Double
        var tier2ConfirmationZThreshold: Double
        var temporalOnsetMinimumSeconds: Double
        var temporalMinimumDurationSeconds: Double
        var temporalMaximumDurationSeconds: Double
        var temporalExitThresholdMultiplier: Double
        var abValidationDays: Int
        var cascadeShadowMode: Bool
        var cueRefractorySeconds: Double
        var cueHourlyBudget: Int
        var throttledCueConfidenceMultiplier: Double
        var minimumEmotionFaceArea: Double
        var minimumEmotionFrameBrightness: Double
        var maximumEmotionFrameBrightness: Double
        var minimumEmotionFrameSharpness: Double

        init(
            tier2SidecarEnabled: Bool,
            tier2SocketPath: String,
            tier2BackgroundFPS: Double,
            tier2BatteryFPS: Double,
            tier2BurstSeconds: Double,
            tier2BurstPrePostSeconds: Double,
            tier1SmileCandidateThreshold: Double,
            tier1MouthOpenCandidateThreshold: Double,
            tier2ConfirmationZThreshold: Double,
            temporalOnsetMinimumSeconds: Double,
            temporalMinimumDurationSeconds: Double,
            temporalMaximumDurationSeconds: Double,
            temporalExitThresholdMultiplier: Double,
            abValidationDays: Int,
            cascadeShadowMode: Bool,
            cueRefractorySeconds: Double,
            cueHourlyBudget: Int,
            throttledCueConfidenceMultiplier: Double,
            minimumEmotionFaceArea: Double,
            minimumEmotionFrameBrightness: Double,
            maximumEmotionFrameBrightness: Double,
            minimumEmotionFrameSharpness: Double
        ) {
            self.tier2SidecarEnabled = tier2SidecarEnabled
            self.tier2SocketPath = tier2SocketPath
            self.tier2BackgroundFPS = tier2BackgroundFPS
            self.tier2BatteryFPS = tier2BatteryFPS
            self.tier2BurstSeconds = tier2BurstSeconds
            self.tier2BurstPrePostSeconds = tier2BurstPrePostSeconds
            self.tier1SmileCandidateThreshold = tier1SmileCandidateThreshold
            self.tier1MouthOpenCandidateThreshold = tier1MouthOpenCandidateThreshold
            self.tier2ConfirmationZThreshold = tier2ConfirmationZThreshold
            self.temporalOnsetMinimumSeconds = temporalOnsetMinimumSeconds
            self.temporalMinimumDurationSeconds = temporalMinimumDurationSeconds
            self.temporalMaximumDurationSeconds = temporalMaximumDurationSeconds
            self.temporalExitThresholdMultiplier = temporalExitThresholdMultiplier
            self.abValidationDays = abValidationDays
            self.cascadeShadowMode = cascadeShadowMode
            self.cueRefractorySeconds = cueRefractorySeconds
            self.cueHourlyBudget = cueHourlyBudget
            self.throttledCueConfidenceMultiplier = throttledCueConfidenceMultiplier
            self.minimumEmotionFaceArea = minimumEmotionFaceArea
            self.minimumEmotionFrameBrightness = minimumEmotionFrameBrightness
            self.maximumEmotionFrameBrightness = maximumEmotionFrameBrightness
            self.minimumEmotionFrameSharpness = minimumEmotionFrameSharpness
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = ObserverSettings.defaults.cameraDetectorSettings
            self.tier2SidecarEnabled = try container.decodeIfPresent(Bool.self, forKey: .tier2SidecarEnabled) ?? defaults.tier2SidecarEnabled
            self.tier2SocketPath = try container.decodeIfPresent(String.self, forKey: .tier2SocketPath) ?? defaults.tier2SocketPath
            self.tier2BackgroundFPS = try container.decodeIfPresent(Double.self, forKey: .tier2BackgroundFPS) ?? defaults.tier2BackgroundFPS
            self.tier2BatteryFPS = try container.decodeIfPresent(Double.self, forKey: .tier2BatteryFPS) ?? defaults.tier2BatteryFPS
            self.tier2BurstSeconds = try container.decodeIfPresent(Double.self, forKey: .tier2BurstSeconds) ?? defaults.tier2BurstSeconds
            self.tier2BurstPrePostSeconds = try container.decodeIfPresent(Double.self, forKey: .tier2BurstPrePostSeconds) ?? defaults.tier2BurstPrePostSeconds
            self.tier1SmileCandidateThreshold = try container.decodeIfPresent(Double.self, forKey: .tier1SmileCandidateThreshold) ?? defaults.tier1SmileCandidateThreshold
            self.tier1MouthOpenCandidateThreshold = try container.decodeIfPresent(Double.self, forKey: .tier1MouthOpenCandidateThreshold) ?? defaults.tier1MouthOpenCandidateThreshold
            self.tier2ConfirmationZThreshold = try container.decodeIfPresent(Double.self, forKey: .tier2ConfirmationZThreshold) ?? defaults.tier2ConfirmationZThreshold
            self.temporalOnsetMinimumSeconds = try container.decodeIfPresent(Double.self, forKey: .temporalOnsetMinimumSeconds) ?? defaults.temporalOnsetMinimumSeconds
            self.temporalMinimumDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .temporalMinimumDurationSeconds) ?? defaults.temporalMinimumDurationSeconds
            self.temporalMaximumDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .temporalMaximumDurationSeconds) ?? defaults.temporalMaximumDurationSeconds
            self.temporalExitThresholdMultiplier = try container.decodeIfPresent(Double.self, forKey: .temporalExitThresholdMultiplier) ?? defaults.temporalExitThresholdMultiplier
            self.abValidationDays = try container.decodeIfPresent(Int.self, forKey: .abValidationDays) ?? defaults.abValidationDays
            self.cascadeShadowMode = try container.decodeIfPresent(Bool.self, forKey: .cascadeShadowMode) ?? defaults.cascadeShadowMode
            self.cueRefractorySeconds = try container.decodeIfPresent(Double.self, forKey: .cueRefractorySeconds) ?? defaults.cueRefractorySeconds
            self.cueHourlyBudget = try container.decodeIfPresent(Int.self, forKey: .cueHourlyBudget) ?? defaults.cueHourlyBudget
            self.throttledCueConfidenceMultiplier = try container.decodeIfPresent(Double.self, forKey: .throttledCueConfidenceMultiplier) ?? defaults.throttledCueConfidenceMultiplier
            self.minimumEmotionFaceArea = try container.decodeIfPresent(Double.self, forKey: .minimumEmotionFaceArea) ?? defaults.minimumEmotionFaceArea
            self.minimumEmotionFrameBrightness = try container.decodeIfPresent(Double.self, forKey: .minimumEmotionFrameBrightness) ?? defaults.minimumEmotionFrameBrightness
            self.maximumEmotionFrameBrightness = try container.decodeIfPresent(Double.self, forKey: .maximumEmotionFrameBrightness) ?? defaults.maximumEmotionFrameBrightness
            self.minimumEmotionFrameSharpness = try container.decodeIfPresent(Double.self, forKey: .minimumEmotionFrameSharpness) ?? defaults.minimumEmotionFrameSharpness
        }
    }

    struct CognitiveSettings: Codable {
        var flowMinimumSeconds: Double
        var flowMaximumFocusChanges: Int
        var activeInputMaximumIdleSeconds: Double
        var readingIdleSeconds: Double
        var wanderingIdleSeconds: Double
        var awayIdleSeconds: Double
        var avoidanceCycles: Int
        var avoidanceWindowSeconds: Double
        var taskFocusShortSeconds: Double
        var overloadDeletionRatioMultiplier: Double
        var predictionIntervalSeconds: Double
        var acceptableBrierScore: Double
        var sequenceMinimumSupport: Int
        var sequenceMinimumConfidence: Double
        var proactiveBlockedStates: [String]
    }

    struct WorkScheduleSettings: Codable {
        var enabled: Bool
        var weekdays: [Int]
        var startHour: Int
        var startMinute: Int
        var endHour: Int
        var endMinute: Int
        var daysOff: [String]
        var gracePeriodSeconds: Double
        var nightlyJobLeadSeconds: Double
        var includeOverridesInBaselines: Bool
        var observeOutsideDefaultSchedule: Bool
        var morningTailMinutes: Double
        var predictionSuppressionBeforeEndSeconds: Double
        var boundaryTruncationMarginSeconds: Double

        init(
            enabled: Bool,
            weekdays: [Int],
            startHour: Int,
            startMinute: Int,
            endHour: Int,
            endMinute: Int,
            daysOff: [String],
            gracePeriodSeconds: Double,
            nightlyJobLeadSeconds: Double,
            includeOverridesInBaselines: Bool,
            observeOutsideDefaultSchedule: Bool,
            morningTailMinutes: Double,
            predictionSuppressionBeforeEndSeconds: Double,
            boundaryTruncationMarginSeconds: Double
        ) {
            self.enabled = enabled
            self.weekdays = weekdays
            self.startHour = startHour
            self.startMinute = startMinute
            self.endHour = endHour
            self.endMinute = endMinute
            self.daysOff = daysOff
            self.gracePeriodSeconds = gracePeriodSeconds
            self.nightlyJobLeadSeconds = nightlyJobLeadSeconds
            self.includeOverridesInBaselines = includeOverridesInBaselines
            self.observeOutsideDefaultSchedule = observeOutsideDefaultSchedule
            self.morningTailMinutes = morningTailMinutes
            self.predictionSuppressionBeforeEndSeconds = predictionSuppressionBeforeEndSeconds
            self.boundaryTruncationMarginSeconds = boundaryTruncationMarginSeconds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = ObserverSettings.defaults.workSchedule
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
            self.weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? defaults.weekdays
            self.startHour = try container.decodeIfPresent(Int.self, forKey: .startHour) ?? defaults.startHour
            self.startMinute = try container.decodeIfPresent(Int.self, forKey: .startMinute) ?? defaults.startMinute
            self.endHour = try container.decodeIfPresent(Int.self, forKey: .endHour) ?? defaults.endHour
            self.endMinute = try container.decodeIfPresent(Int.self, forKey: .endMinute) ?? defaults.endMinute
            self.daysOff = try container.decodeIfPresent([String].self, forKey: .daysOff) ?? defaults.daysOff
            self.gracePeriodSeconds = try container.decodeIfPresent(Double.self, forKey: .gracePeriodSeconds) ?? defaults.gracePeriodSeconds
            self.nightlyJobLeadSeconds = try container.decodeIfPresent(Double.self, forKey: .nightlyJobLeadSeconds) ?? defaults.nightlyJobLeadSeconds
            self.includeOverridesInBaselines = try container.decodeIfPresent(Bool.self, forKey: .includeOverridesInBaselines) ?? defaults.includeOverridesInBaselines
            self.observeOutsideDefaultSchedule = try container.decodeIfPresent(Bool.self, forKey: .observeOutsideDefaultSchedule) ?? defaults.observeOutsideDefaultSchedule
            self.morningTailMinutes = try container.decodeIfPresent(Double.self, forKey: .morningTailMinutes) ?? defaults.morningTailMinutes
            self.predictionSuppressionBeforeEndSeconds = try container.decodeIfPresent(Double.self, forKey: .predictionSuppressionBeforeEndSeconds) ?? defaults.predictionSuppressionBeforeEndSeconds
            self.boundaryTruncationMarginSeconds = try container.decodeIfPresent(Double.self, forKey: .boundaryTruncationMarginSeconds) ?? defaults.boundaryTruncationMarginSeconds
        }
    }

    struct ReadinessSettings: Codable {
        var cognitiveStateMinimumEvents: Int
        var cognitiveStateMinimumDays: Int
        var boundReactionMinimumEvents: Int
        var boundReactionMinimumEntitiesOrTopics: Int
        var geminiInsightMinimumEvents: Int
        var fusionCompressionMinimum: Double
        var fusionCompressionMaximum: Double
        var fusionAuditSampleSize: Int
        var minimumIndependentEpisodes: Int
        var minimumEpisodeDays: Int
        var minimumLineageCoverage: Double
        var minimumEpisodeContentCoverage: Double
        var maximumUnsupportedClaimRate: Double

        init(
            cognitiveStateMinimumEvents: Int,
            cognitiveStateMinimumDays: Int,
            boundReactionMinimumEvents: Int,
            boundReactionMinimumEntitiesOrTopics: Int,
            geminiInsightMinimumEvents: Int,
            fusionCompressionMinimum: Double,
            fusionCompressionMaximum: Double,
            fusionAuditSampleSize: Int,
            minimumIndependentEpisodes: Int,
            minimumEpisodeDays: Int,
            minimumLineageCoverage: Double,
            minimumEpisodeContentCoverage: Double,
            maximumUnsupportedClaimRate: Double
        ) {
            self.cognitiveStateMinimumEvents = cognitiveStateMinimumEvents
            self.cognitiveStateMinimumDays = cognitiveStateMinimumDays
            self.boundReactionMinimumEvents = boundReactionMinimumEvents
            self.boundReactionMinimumEntitiesOrTopics = boundReactionMinimumEntitiesOrTopics
            self.geminiInsightMinimumEvents = geminiInsightMinimumEvents
            self.fusionCompressionMinimum = fusionCompressionMinimum
            self.fusionCompressionMaximum = fusionCompressionMaximum
            self.fusionAuditSampleSize = fusionAuditSampleSize
            self.minimumIndependentEpisodes = minimumIndependentEpisodes
            self.minimumEpisodeDays = minimumEpisodeDays
            self.minimumLineageCoverage = minimumLineageCoverage
            self.minimumEpisodeContentCoverage = minimumEpisodeContentCoverage
            self.maximumUnsupportedClaimRate = maximumUnsupportedClaimRate
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = ObserverSettings.defaults.readinessSettings
            self.cognitiveStateMinimumEvents = try container.decodeIfPresent(Int.self, forKey: .cognitiveStateMinimumEvents) ?? defaults.cognitiveStateMinimumEvents
            self.cognitiveStateMinimumDays = try container.decodeIfPresent(Int.self, forKey: .cognitiveStateMinimumDays) ?? defaults.cognitiveStateMinimumDays
            self.boundReactionMinimumEvents = try container.decodeIfPresent(Int.self, forKey: .boundReactionMinimumEvents) ?? defaults.boundReactionMinimumEvents
            self.boundReactionMinimumEntitiesOrTopics = try container.decodeIfPresent(Int.self, forKey: .boundReactionMinimumEntitiesOrTopics) ?? defaults.boundReactionMinimumEntitiesOrTopics
            self.geminiInsightMinimumEvents = try container.decodeIfPresent(Int.self, forKey: .geminiInsightMinimumEvents) ?? defaults.geminiInsightMinimumEvents
            self.fusionCompressionMinimum = try container.decodeIfPresent(Double.self, forKey: .fusionCompressionMinimum) ?? defaults.fusionCompressionMinimum
            self.fusionCompressionMaximum = try container.decodeIfPresent(Double.self, forKey: .fusionCompressionMaximum) ?? defaults.fusionCompressionMaximum
            self.fusionAuditSampleSize = try container.decodeIfPresent(Int.self, forKey: .fusionAuditSampleSize) ?? defaults.fusionAuditSampleSize
            self.minimumIndependentEpisodes = try container.decodeIfPresent(Int.self, forKey: .minimumIndependentEpisodes) ?? defaults.minimumIndependentEpisodes
            self.minimumEpisodeDays = try container.decodeIfPresent(Int.self, forKey: .minimumEpisodeDays) ?? defaults.minimumEpisodeDays
            self.minimumLineageCoverage = try container.decodeIfPresent(Double.self, forKey: .minimumLineageCoverage) ?? defaults.minimumLineageCoverage
            self.minimumEpisodeContentCoverage = try container.decodeIfPresent(Double.self, forKey: .minimumEpisodeContentCoverage) ?? defaults.minimumEpisodeContentCoverage
            self.maximumUnsupportedClaimRate = try container.decodeIfPresent(Double.self, forKey: .maximumUnsupportedClaimRate) ?? defaults.maximumUnsupportedClaimRate
        }
    }

    struct ContextFabricSettings: Codable {
        var contextFabricEnabled: Bool
        var cameraEvidenceEnabled: Bool
        var objectGestureLayerEnabled: Bool
        var episodeEngineEnabled: Bool
        var contextLinkerEnabled: Bool
        var activityTrackerEnabled: Bool
        var activityTrackerShadowMode: Bool
        var activityTrackerUIEnabled: Bool
        var activityThreadRelinkerEnabled: Bool
        var causalLayerShadowMode: Bool
        var meetingCallUnderstandingEnabled: Bool
        var meetingAppPatterns: [String]
        var callAppPatterns: [String]
        var callSystemAudioEnabledByDefault: Bool
        var objectPresenceShadowMode: Bool
        var objectPresenceFPS: Double
        var objectPresenceBatteryFPS: Double
        var objectPresenceDisabledDuringMeeting: Bool

        init(
            contextFabricEnabled: Bool,
            cameraEvidenceEnabled: Bool,
            objectGestureLayerEnabled: Bool,
            episodeEngineEnabled: Bool,
            contextLinkerEnabled: Bool,
            activityTrackerEnabled: Bool,
            activityTrackerShadowMode: Bool,
            activityTrackerUIEnabled: Bool,
            activityThreadRelinkerEnabled: Bool,
            causalLayerShadowMode: Bool,
            meetingCallUnderstandingEnabled: Bool,
            meetingAppPatterns: [String],
            callAppPatterns: [String],
            callSystemAudioEnabledByDefault: Bool,
            objectPresenceShadowMode: Bool,
            objectPresenceFPS: Double,
            objectPresenceBatteryFPS: Double,
            objectPresenceDisabledDuringMeeting: Bool
        ) {
            self.contextFabricEnabled = contextFabricEnabled
            self.cameraEvidenceEnabled = cameraEvidenceEnabled
            self.objectGestureLayerEnabled = objectGestureLayerEnabled
            self.episodeEngineEnabled = episodeEngineEnabled
            self.contextLinkerEnabled = contextLinkerEnabled
            self.activityTrackerEnabled = activityTrackerEnabled
            self.activityTrackerShadowMode = activityTrackerShadowMode
            self.activityTrackerUIEnabled = activityTrackerUIEnabled
            self.activityThreadRelinkerEnabled = activityThreadRelinkerEnabled
            self.causalLayerShadowMode = causalLayerShadowMode
            self.meetingCallUnderstandingEnabled = meetingCallUnderstandingEnabled
            self.meetingAppPatterns = meetingAppPatterns
            self.callAppPatterns = callAppPatterns
            self.callSystemAudioEnabledByDefault = callSystemAudioEnabledByDefault
            self.objectPresenceShadowMode = objectPresenceShadowMode
            self.objectPresenceFPS = objectPresenceFPS
            self.objectPresenceBatteryFPS = objectPresenceBatteryFPS
            self.objectPresenceDisabledDuringMeeting = objectPresenceDisabledDuringMeeting
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = ObserverSettings.defaults.contextFabric
            self.contextFabricEnabled = try container.decodeIfPresent(Bool.self, forKey: .contextFabricEnabled) ?? defaults.contextFabricEnabled
            self.cameraEvidenceEnabled = try container.decodeIfPresent(Bool.self, forKey: .cameraEvidenceEnabled) ?? defaults.cameraEvidenceEnabled
            self.objectGestureLayerEnabled = try container.decodeIfPresent(Bool.self, forKey: .objectGestureLayerEnabled) ?? defaults.objectGestureLayerEnabled
            self.episodeEngineEnabled = try container.decodeIfPresent(Bool.self, forKey: .episodeEngineEnabled) ?? defaults.episodeEngineEnabled
            self.contextLinkerEnabled = try container.decodeIfPresent(Bool.self, forKey: .contextLinkerEnabled) ?? defaults.contextLinkerEnabled
            self.activityTrackerEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityTrackerEnabled) ?? defaults.activityTrackerEnabled
            self.activityTrackerShadowMode = try container.decodeIfPresent(Bool.self, forKey: .activityTrackerShadowMode) ?? defaults.activityTrackerShadowMode
            self.activityTrackerUIEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityTrackerUIEnabled) ?? defaults.activityTrackerUIEnabled
            self.activityThreadRelinkerEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityThreadRelinkerEnabled) ?? defaults.activityThreadRelinkerEnabled
            self.causalLayerShadowMode = try container.decodeIfPresent(Bool.self, forKey: .causalLayerShadowMode) ?? defaults.causalLayerShadowMode
            self.meetingCallUnderstandingEnabled = try container.decodeIfPresent(Bool.self, forKey: .meetingCallUnderstandingEnabled) ?? defaults.meetingCallUnderstandingEnabled
            self.meetingAppPatterns = try container.decodeIfPresent([String].self, forKey: .meetingAppPatterns) ?? defaults.meetingAppPatterns
            self.callAppPatterns = try container.decodeIfPresent([String].self, forKey: .callAppPatterns) ?? defaults.callAppPatterns
            self.callSystemAudioEnabledByDefault = try container.decodeIfPresent(Bool.self, forKey: .callSystemAudioEnabledByDefault) ?? defaults.callSystemAudioEnabledByDefault
            self.objectPresenceShadowMode = try container.decodeIfPresent(Bool.self, forKey: .objectPresenceShadowMode) ?? defaults.objectPresenceShadowMode
            self.objectPresenceFPS = try container.decodeIfPresent(Double.self, forKey: .objectPresenceFPS) ?? defaults.objectPresenceFPS
            self.objectPresenceBatteryFPS = try container.decodeIfPresent(Double.self, forKey: .objectPresenceBatteryFPS) ?? defaults.objectPresenceBatteryFPS
            self.objectPresenceDisabledDuringMeeting = try container.decodeIfPresent(Bool.self, forKey: .objectPresenceDisabledDuringMeeting) ?? defaults.objectPresenceDisabledDuringMeeting
        }
    }

    struct DashboardSettings: Codable {
        var enabled: Bool
        var port: Int
        var remoteAccessMode: String
        var diagnosticsEnabled: Bool
        var sessionTTLSeconds: Double

        init(
            enabled: Bool,
            port: Int,
            remoteAccessMode: String,
            diagnosticsEnabled: Bool,
            sessionTTLSeconds: Double
        ) {
            self.enabled = enabled
            self.port = port
            self.remoteAccessMode = remoteAccessMode
            self.diagnosticsEnabled = diagnosticsEnabled
            self.sessionTTLSeconds = sessionTTLSeconds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = ObserverSettings.defaults.dashboard
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
            self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? defaults.port
            self.remoteAccessMode = try container.decodeIfPresent(String.self, forKey: .remoteAccessMode) ?? defaults.remoteAccessMode
            self.diagnosticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagnosticsEnabled) ?? defaults.diagnosticsEnabled
            self.sessionTTLSeconds = try container.decodeIfPresent(Double.self, forKey: .sessionTTLSeconds) ?? defaults.sessionTTLSeconds
        }
    }

    var summaryIntervalSeconds: TimeInterval
    var retentionDays: Int
    var idleSessionBoundarySeconds: Double
    var startObservingOnLaunch: Bool
    var startCameraAttentionOnLaunch: Bool
    var hintDeliveryMode: String
    var minimumHintIntervalSeconds: Double
    var attentionSampleIntervalSeconds: Double
    var screenContextRefreshSeconds: Double
    var geminiEnabled: Bool
    var geminiModel: String
    var geminiDailyBudgetEUR: Double
    var geminiEstimatedCostPerRequestEUR: Double
    var geminiAutoInsightEnabled: Bool
    var geminiAutoInsightIntervalSeconds: Double
    var autoPauseMediaWhenAway: Bool
    var autoResumeMediaWhenBack: Bool
    var fullContextMode: Bool
    var rawContextStorageKinds: [String]
    var pillVerbosity: String
    var pseudonymizeEntities: Bool
    var detectorSettings: DetectorSettings
    var cameraDetectorSettings: CameraDetectorSettings
    var cognitiveSettings: CognitiveSettings
    var workSchedule: WorkScheduleSettings
    var readinessSettings: ReadinessSettings
    var contextFabric: ContextFabricSettings
    var dashboard: DashboardSettings

    init(
        summaryIntervalSeconds: TimeInterval,
        retentionDays: Int,
        idleSessionBoundarySeconds: Double,
        startObservingOnLaunch: Bool,
        startCameraAttentionOnLaunch: Bool,
        hintDeliveryMode: String,
        minimumHintIntervalSeconds: Double,
        attentionSampleIntervalSeconds: Double,
        screenContextRefreshSeconds: Double,
        geminiEnabled: Bool,
        geminiModel: String,
        geminiDailyBudgetEUR: Double,
        geminiEstimatedCostPerRequestEUR: Double,
        geminiAutoInsightEnabled: Bool,
        geminiAutoInsightIntervalSeconds: Double,
        autoPauseMediaWhenAway: Bool,
        autoResumeMediaWhenBack: Bool,
        fullContextMode: Bool,
        rawContextStorageKinds: [String],
        pillVerbosity: String,
        pseudonymizeEntities: Bool,
        detectorSettings: DetectorSettings,
        cameraDetectorSettings: CameraDetectorSettings,
        cognitiveSettings: CognitiveSettings,
        workSchedule: WorkScheduleSettings,
        readinessSettings: ReadinessSettings,
        contextFabric: ContextFabricSettings,
        dashboard: DashboardSettings
    ) {
        self.summaryIntervalSeconds = summaryIntervalSeconds
        self.retentionDays = retentionDays
        self.idleSessionBoundarySeconds = idleSessionBoundarySeconds
        self.startObservingOnLaunch = startObservingOnLaunch
        self.startCameraAttentionOnLaunch = startCameraAttentionOnLaunch
        self.hintDeliveryMode = hintDeliveryMode
        self.minimumHintIntervalSeconds = minimumHintIntervalSeconds
        self.attentionSampleIntervalSeconds = attentionSampleIntervalSeconds
        self.screenContextRefreshSeconds = screenContextRefreshSeconds
        self.geminiEnabled = geminiEnabled
        self.geminiModel = geminiModel
        self.geminiDailyBudgetEUR = geminiDailyBudgetEUR
        self.geminiEstimatedCostPerRequestEUR = geminiEstimatedCostPerRequestEUR
        self.geminiAutoInsightEnabled = geminiAutoInsightEnabled
        self.geminiAutoInsightIntervalSeconds = geminiAutoInsightIntervalSeconds
        self.autoPauseMediaWhenAway = autoPauseMediaWhenAway
        self.autoResumeMediaWhenBack = autoResumeMediaWhenBack
        self.fullContextMode = fullContextMode
        self.rawContextStorageKinds = rawContextStorageKinds
        self.pillVerbosity = pillVerbosity
        self.pseudonymizeEntities = pseudonymizeEntities
        self.detectorSettings = detectorSettings
        self.cameraDetectorSettings = cameraDetectorSettings
        self.cognitiveSettings = cognitiveSettings
        self.workSchedule = workSchedule
        self.readinessSettings = readinessSettings
        self.contextFabric = contextFabric
        self.dashboard = dashboard
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        self.summaryIntervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .summaryIntervalSeconds) ?? defaults.summaryIntervalSeconds
        self.retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? defaults.retentionDays
        self.idleSessionBoundarySeconds = try container.decodeIfPresent(Double.self, forKey: .idleSessionBoundarySeconds) ?? defaults.idleSessionBoundarySeconds
        self.startObservingOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .startObservingOnLaunch) ?? defaults.startObservingOnLaunch
        self.startCameraAttentionOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .startCameraAttentionOnLaunch) ?? defaults.startCameraAttentionOnLaunch
        self.hintDeliveryMode = try container.decodeIfPresent(String.self, forKey: .hintDeliveryMode) ?? defaults.hintDeliveryMode
        self.minimumHintIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .minimumHintIntervalSeconds) ?? defaults.minimumHintIntervalSeconds
        self.attentionSampleIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .attentionSampleIntervalSeconds) ?? defaults.attentionSampleIntervalSeconds
        self.screenContextRefreshSeconds = try container.decodeIfPresent(Double.self, forKey: .screenContextRefreshSeconds) ?? defaults.screenContextRefreshSeconds
        self.geminiEnabled = try container.decodeIfPresent(Bool.self, forKey: .geminiEnabled) ?? defaults.geminiEnabled
        self.geminiModel = try container.decodeIfPresent(String.self, forKey: .geminiModel) ?? defaults.geminiModel
        self.geminiDailyBudgetEUR = try container.decodeIfPresent(Double.self, forKey: .geminiDailyBudgetEUR) ?? defaults.geminiDailyBudgetEUR
        self.geminiEstimatedCostPerRequestEUR = try container.decodeIfPresent(Double.self, forKey: .geminiEstimatedCostPerRequestEUR) ?? defaults.geminiEstimatedCostPerRequestEUR
        self.geminiAutoInsightEnabled = try container.decodeIfPresent(Bool.self, forKey: .geminiAutoInsightEnabled) ?? defaults.geminiAutoInsightEnabled
        self.geminiAutoInsightIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .geminiAutoInsightIntervalSeconds) ?? defaults.geminiAutoInsightIntervalSeconds
        self.autoPauseMediaWhenAway = try container.decodeIfPresent(Bool.self, forKey: .autoPauseMediaWhenAway) ?? defaults.autoPauseMediaWhenAway
        self.autoResumeMediaWhenBack = try container.decodeIfPresent(Bool.self, forKey: .autoResumeMediaWhenBack) ?? defaults.autoResumeMediaWhenBack
        self.fullContextMode = try container.decodeIfPresent(Bool.self, forKey: .fullContextMode) ?? defaults.fullContextMode
        self.rawContextStorageKinds = try container.decodeIfPresent([String].self, forKey: .rawContextStorageKinds) ?? defaults.rawContextStorageKinds
        self.pillVerbosity = try container.decodeIfPresent(String.self, forKey: .pillVerbosity) ?? defaults.pillVerbosity
        self.pseudonymizeEntities = try container.decodeIfPresent(Bool.self, forKey: .pseudonymizeEntities) ?? defaults.pseudonymizeEntities
        self.detectorSettings = try container.decodeIfPresent(DetectorSettings.self, forKey: .detectorSettings) ?? defaults.detectorSettings
        self.cameraDetectorSettings = try container.decodeIfPresent(CameraDetectorSettings.self, forKey: .cameraDetectorSettings) ?? defaults.cameraDetectorSettings
        self.cognitiveSettings = try container.decodeIfPresent(CognitiveSettings.self, forKey: .cognitiveSettings) ?? defaults.cognitiveSettings
        self.workSchedule = try container.decodeIfPresent(WorkScheduleSettings.self, forKey: .workSchedule) ?? defaults.workSchedule
        self.readinessSettings = try container.decodeIfPresent(ReadinessSettings.self, forKey: .readinessSettings) ?? defaults.readinessSettings
        self.contextFabric = try container.decodeIfPresent(ContextFabricSettings.self, forKey: .contextFabric) ?? defaults.contextFabric
        self.dashboard = try container.decodeIfPresent(DashboardSettings.self, forKey: .dashboard) ?? defaults.dashboard
    }

    static let defaults = ObserverSettings(
        summaryIntervalSeconds: 2700,
        retentionDays: 90,
        idleSessionBoundarySeconds: 300,
        startObservingOnLaunch: true,
        startCameraAttentionOnLaunch: true,
        hintDeliveryMode: "quiet",
        minimumHintIntervalSeconds: 1800,
        attentionSampleIntervalSeconds: 5,
        screenContextRefreshSeconds: 60,
        geminiEnabled: true,
        geminiModel: "gemini-3.5-flash",
        geminiDailyBudgetEUR: 2.0,
        geminiEstimatedCostPerRequestEUR: 0.02,
        geminiAutoInsightEnabled: true,
        geminiAutoInsightIntervalSeconds: 1800,
        autoPauseMediaWhenAway: true,
        autoResumeMediaWhenBack: true,
        fullContextMode: true,
        rawContextStorageKinds: ["prompt", "code", "doc"],
        pillVerbosity: "task_only",
        pseudonymizeEntities: true,
        detectorSettings: DetectorSettings(
            frequentSwitchFocusEvents: 8,
            frequentSwitchUniqueApps: 2,
            returnLoopMinimumEvents: 5,
            returnLoopMinimumReturns: 3,
            readingPauseSeconds: 180
        ),
        cameraDetectorSettings: CameraDetectorSettings(
            tier2SidecarEnabled: false,
            tier2SocketPath: "/tmp/observer-openface3.sock",
            tier2BackgroundFPS: 2.0,
            tier2BatteryFPS: 1.0,
            tier2BurstSeconds: 10.0,
            tier2BurstPrePostSeconds: 3.0,
            tier1SmileCandidateThreshold: 0.48,
            tier1MouthOpenCandidateThreshold: 0.50,
            tier2ConfirmationZThreshold: 1.35,
            temporalOnsetMinimumSeconds: 0.30,
            temporalMinimumDurationSeconds: 0.50,
            temporalMaximumDurationSeconds: 4.0,
            temporalExitThresholdMultiplier: 0.65,
            abValidationDays: 14,
            cascadeShadowMode: true,
            cueRefractorySeconds: 60,
            cueHourlyBudget: 12,
            throttledCueConfidenceMultiplier: 0.55,
            minimumEmotionFaceArea: 0.012,
            minimumEmotionFrameBrightness: 0.08,
            maximumEmotionFrameBrightness: 0.92,
            minimumEmotionFrameSharpness: 0.006
        ),
        cognitiveSettings: CognitiveSettings(
            flowMinimumSeconds: 600,
            flowMaximumFocusChanges: 0,
            activeInputMaximumIdleSeconds: 15,
            readingIdleSeconds: 30,
            wanderingIdleSeconds: 60,
            awayIdleSeconds: 45,
            avoidanceCycles: 3,
            avoidanceWindowSeconds: 900,
            taskFocusShortSeconds: 90,
            overloadDeletionRatioMultiplier: 2,
            predictionIntervalSeconds: 300,
            acceptableBrierScore: 0.20,
            sequenceMinimumSupport: 3,
            sequenceMinimumConfidence: 0.60,
            proactiveBlockedStates: ["flow"]
        ),
        workSchedule: WorkScheduleSettings(
            enabled: true,
            weekdays: [2, 3, 4, 5, 6],
            startHour: 9,
            startMinute: 0,
            endHour: 18,
            endMinute: 0,
            daysOff: [],
            gracePeriodSeconds: 300,
            nightlyJobLeadSeconds: 3600,
            includeOverridesInBaselines: false,
            observeOutsideDefaultSchedule: true,
            morningTailMinutes: 10,
            predictionSuppressionBeforeEndSeconds: 1800,
            boundaryTruncationMarginSeconds: 300
        ),
        readinessSettings: ReadinessSettings(
            cognitiveStateMinimumEvents: 500,
            cognitiveStateMinimumDays: 5,
            boundReactionMinimumEvents: 200,
            boundReactionMinimumEntitiesOrTopics: 15,
            geminiInsightMinimumEvents: 20,
            fusionCompressionMinimum: 0.30,
            fusionCompressionMaximum: 0.50,
            fusionAuditSampleSize: 30,
            minimumIndependentEpisodes: 50,
            minimumEpisodeDays: 5,
            minimumLineageCoverage: 0.95,
            minimumEpisodeContentCoverage: 0.80,
            maximumUnsupportedClaimRate: 0.05
        ),
        contextFabric: ContextFabricSettings(
            contextFabricEnabled: true,
            cameraEvidenceEnabled: true,
            objectGestureLayerEnabled: true,
            episodeEngineEnabled: true,
            contextLinkerEnabled: true,
            activityTrackerEnabled: true,
            activityTrackerShadowMode: true,
            activityTrackerUIEnabled: true,
            activityThreadRelinkerEnabled: true,
            causalLayerShadowMode: true,
            meetingCallUnderstandingEnabled: true,
            meetingAppPatterns: ["meet.google.com", "google meet", "zoom", "teams.microsoft.com", "microsoft teams", "webex"],
            callAppPatterns: ["viber", "whatsapp", "telegram", "facetime"],
            callSystemAudioEnabledByDefault: true,
            objectPresenceShadowMode: true,
            objectPresenceFPS: 1.0,
            objectPresenceBatteryFPS: 0.5,
            objectPresenceDisabledDuringMeeting: true
        ),
        dashboard: DashboardSettings(
            enabled: true,
            port: 43127,
            remoteAccessMode: "off",
            diagnosticsEnabled: true,
            sessionTTLSeconds: 60 * 60 * 12
        )
    )
}
