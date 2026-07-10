import Foundation

struct ObserverSettings: Codable {
    struct DetectorSettings: Codable {
        var frequentSwitchFocusEvents: Int
        var frequentSwitchUniqueApps: Int
        var returnLoopMinimumEvents: Int
        var returnLoopMinimumReturns: Int
        var readingPauseSeconds: Double
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
    var detectorSettings: DetectorSettings

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
        detectorSettings: DetectorSettings
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
        self.detectorSettings = detectorSettings
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
        self.detectorSettings = try container.decodeIfPresent(DetectorSettings.self, forKey: .detectorSettings) ?? defaults.detectorSettings
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
        detectorSettings: DetectorSettings(
            frequentSwitchFocusEvents: 8,
            frequentSwitchUniqueApps: 2,
            returnLoopMinimumEvents: 5,
            returnLoopMinimumReturns: 3,
            readingPauseSeconds: 180
        )
    )
}
