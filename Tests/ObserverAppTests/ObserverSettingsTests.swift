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
        #expect(settings.startObservingOnLaunch == true)
        #expect(settings.startCameraAttentionOnLaunch == true)
        #expect(settings.hintDeliveryMode == "quiet")
        #expect(settings.minimumHintIntervalSeconds == 1800)
        #expect(settings.attentionSampleIntervalSeconds == ObserverSettings.defaults.attentionSampleIntervalSeconds)
        #expect(settings.screenContextRefreshSeconds == 60)
        #expect(settings.geminiEnabled == true)
        #expect(settings.geminiModel == "gemini-3.5-flash")
        #expect(settings.geminiAutoInsightEnabled == true)
        #expect(settings.geminiAutoInsightIntervalSeconds == 1800)
        #expect(settings.autoPauseMediaWhenAway == true)
        #expect(settings.autoResumeMediaWhenBack == true)
        #expect(settings.fullContextMode == true)
        #expect(settings.rawContextStorageKinds == ["prompt", "code", "doc"])
        #expect(settings.pillVerbosity == "task_only")
        #expect(settings.pseudonymizeEntities == true)
        #expect(settings.workSchedule.observeOutsideDefaultSchedule == true)
    }
}
