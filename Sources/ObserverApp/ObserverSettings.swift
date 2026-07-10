import Foundation

struct ObserverSettings: Codable {
    struct DetectorSettings: Codable {
        var frequentSwitchFocusEvents: Int
        var frequentSwitchUniqueApps: Int
        var returnLoopMinimumEvents: Int
        var returnLoopMinimumReturns: Int
        var readingPauseSeconds: Double
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
        var morningTailMinutes: Double
        var predictionSuppressionBeforeEndSeconds: Double
        var boundaryTruncationMarginSeconds: Double
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
    var autoPauseMediaWhenAway: Bool
    var autoResumeMediaWhenBack: Bool
    var fullContextMode: Bool
    var rawContextStorageKinds: [String]
    var pillVerbosity: String
    var pseudonymizeEntities: Bool
    var detectorSettings: DetectorSettings
    var cognitiveSettings: CognitiveSettings
    var workSchedule: WorkScheduleSettings

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
        autoPauseMediaWhenAway: Bool,
        autoResumeMediaWhenBack: Bool,
        fullContextMode: Bool,
        rawContextStorageKinds: [String],
        pillVerbosity: String,
        pseudonymizeEntities: Bool,
        detectorSettings: DetectorSettings,
        cognitiveSettings: CognitiveSettings,
        workSchedule: WorkScheduleSettings
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
        self.autoPauseMediaWhenAway = autoPauseMediaWhenAway
        self.autoResumeMediaWhenBack = autoResumeMediaWhenBack
        self.fullContextMode = fullContextMode
        self.rawContextStorageKinds = rawContextStorageKinds
        self.pillVerbosity = pillVerbosity
        self.pseudonymizeEntities = pseudonymizeEntities
        self.detectorSettings = detectorSettings
        self.cognitiveSettings = cognitiveSettings
        self.workSchedule = workSchedule
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
        self.autoPauseMediaWhenAway = try container.decodeIfPresent(Bool.self, forKey: .autoPauseMediaWhenAway) ?? defaults.autoPauseMediaWhenAway
        self.autoResumeMediaWhenBack = try container.decodeIfPresent(Bool.self, forKey: .autoResumeMediaWhenBack) ?? defaults.autoResumeMediaWhenBack
        self.fullContextMode = try container.decodeIfPresent(Bool.self, forKey: .fullContextMode) ?? defaults.fullContextMode
        self.rawContextStorageKinds = try container.decodeIfPresent([String].self, forKey: .rawContextStorageKinds) ?? defaults.rawContextStorageKinds
        self.pillVerbosity = try container.decodeIfPresent(String.self, forKey: .pillVerbosity) ?? defaults.pillVerbosity
        self.pseudonymizeEntities = try container.decodeIfPresent(Bool.self, forKey: .pseudonymizeEntities) ?? defaults.pseudonymizeEntities
        self.detectorSettings = try container.decodeIfPresent(DetectorSettings.self, forKey: .detectorSettings) ?? defaults.detectorSettings
        self.cognitiveSettings = try container.decodeIfPresent(CognitiveSettings.self, forKey: .cognitiveSettings) ?? defaults.cognitiveSettings
        self.workSchedule = try container.decodeIfPresent(WorkScheduleSettings.self, forKey: .workSchedule) ?? defaults.workSchedule
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
            morningTailMinutes: 10,
            predictionSuppressionBeforeEndSeconds: 1800,
            boundaryTruncationMarginSeconds: 300
        )
    )
}
