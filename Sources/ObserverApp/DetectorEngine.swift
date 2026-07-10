import Foundation

struct DetectorEngine {
    private let settings: ObserverSettings.DetectorSettings

    struct Detection {
        let name: String
        let confidence: Double
        let payload: [String: String]
    }

    init(settings: ObserverSettings.DetectorSettings = ObserverSettings.defaults.detectorSettings) {
        self.settings = settings
    }

    func evaluate(events: [ObserverEvent]) -> [Detection] {
        let recentEvents = events.suffix(120)
        let appFocusEvents = recentEvents.filter { $0.type == .appFocus }
        let inputEvents = recentEvents.filter { $0.type == .inputActivity }
        let attentionEvents = recentEvents.filter { $0.type == .attention }

        return [
            appSwitchingDetection(appFocusEvents),
            returnLoopDetection(appFocusEvents),
            readingOrThinkingDetection(inputEvents: inputEvents, attentionEvents: attentionEvents)
        ].compactMap { $0 }
    }

    private func appSwitchingDetection(_ events: [ObserverEvent]) -> Detection? {
        let apps = events.compactMap { $0.payload["app_name"] ?? $0.appID }
        let uniqueApps = Set(apps)
        guard apps.count >= settings.frequentSwitchFocusEvents,
              uniqueApps.count >= settings.frequentSwitchUniqueApps
        else {
            return nil
        }

        return Detection(
            name: "frequent_app_switching",
            confidence: min(0.9, 0.45 + Double(apps.count) / 30.0),
            payload: [
                "detector": "frequent_app_switching",
                "focus_events": "\(apps.count)",
                "unique_apps": "\(uniqueApps.count)",
                "interpretation": "possible context switching or active comparison"
            ]
        )
    }

    private func returnLoopDetection(_ events: [ObserverEvent]) -> Detection? {
        let apps = events.compactMap { $0.payload["app_name"] ?? $0.appID }
        guard apps.count >= settings.returnLoopMinimumEvents else {
            return nil
        }

        let counts = apps.reduce(into: [String: Int]()) { result, app in
            result[app, default: 0] += 1
        }

        guard let repeated = counts.max(by: { $0.value < $1.value }),
              repeated.value >= settings.returnLoopMinimumReturns
        else {
            return nil
        }

        return Detection(
            name: "return_loop",
            confidence: min(0.85, 0.4 + Double(repeated.value) / 10.0),
            payload: [
                "detector": "return_loop",
                "app": repeated.key,
                "returns": "\(repeated.value)",
                "interpretation": "possible repeated return to the same context"
            ]
        )
    }

    private func readingOrThinkingDetection(
        inputEvents: [ObserverEvent],
        attentionEvents: [ObserverEvent]
    ) -> Detection? {
        guard
            let input = inputEvents.last,
            let idleText = input.payload["seconds_since_any_input"],
            let idle = Double(idleText),
            idle >= settings.readingPauseSeconds
        else {
            return nil
        }

        let facePresent = attentionEvents.last?.payload["face_present"] == "true"
        return Detection(
            name: "reading_or_thinking",
            confidence: facePresent ? 0.75 : 0.55,
            payload: [
                "detector": "reading_or_thinking",
                "seconds_since_any_input": String(format: "%.1f", idle),
                "face_present": facePresent ? "true" : "unknown",
                "interpretation": "static work may be reading or thinking; avoid interruption"
            ]
        )
    }
}
