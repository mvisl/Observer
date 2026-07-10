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
        self.detectorSettings = try container.decodeIfPresent(DetectorSettings.self, forKey: .detectorSettings) ?? defaults.detectorSettings
    }

    static let defaults = ObserverSettings(
        summaryIntervalSeconds: 900,
        retentionDays: 90,
        idleSessionBoundarySeconds: 300,
        startObservingOnLaunch: false,
        startCameraAttentionOnLaunch: false,
        hintDeliveryMode: "quiet",
        minimumHintIntervalSeconds: 1800,
        attentionSampleIntervalSeconds: 15,
        screenContextRefreshSeconds: 60,
        detectorSettings: DetectorSettings(
            frequentSwitchFocusEvents: 8,
            frequentSwitchUniqueApps: 2,
            returnLoopMinimumEvents: 5,
            returnLoopMinimumReturns: 3,
            readingPauseSeconds: 180
        )
    )
}
