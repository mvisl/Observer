import Foundation
import Testing
@testable import ObserverApp

struct ObserverSettingsTests {
    @Test func decodesOldSettingsWithDefaults() throws {
        let data = Data("""
        {
          "summaryIntervalSeconds": 900,
          "retentionDays": 90,
          "detectorSettings": {
            "frequentSwitchFocusEvents": 8,
            "frequentSwitchUniqueApps": 2,
            "readingPauseSeconds": 180,
            "returnLoopMinimumEvents": 5,
            "returnLoopMinimumReturns": 3
          }
        }
        """.utf8)

        let settings = try JSONDecoder().decode(ObserverSettings.self, from: data)
        #expect(settings.idleSessionBoundarySeconds == ObserverSettings.defaults.idleSessionBoundarySeconds)
        #expect(settings.startObservingOnLaunch == false)
        #expect(settings.startCameraAttentionOnLaunch == false)
        #expect(settings.hintDeliveryMode == "quiet")
        #expect(settings.minimumHintIntervalSeconds == 1800)
        #expect(settings.attentionSampleIntervalSeconds == 15)
        #expect(settings.screenContextRefreshSeconds == 60)
    }
}
