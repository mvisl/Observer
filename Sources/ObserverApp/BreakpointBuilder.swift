import Foundation

struct BreakpointBuilder {
    func fineInputPause(secondsSinceAnyInput: Double) -> [String: String]? {
        guard secondsSinceAnyInput >= 30 else {
            return nil
        }
        return [
            "level": "fine",
            "reason": "input_pause",
            "seconds_since_any_input": String(format: "%.1f", secondsSinceAnyInput)
        ]
    }

    func mediumFocusChange(previousAppName: String?, nextFocus: AppFocusSnapshot) -> [String: String] {
        var payload: [String: String] = [
            "level": "medium",
            "reason": "focus_changed",
            "app_name": nextFocus.appName
        ]
        if let previousAppName {
            payload["previous_app_name"] = previousAppName
        }
        if let appID = nextFocus.appID {
            payload["app_id"] = appID
        }
        if let displayRole = nextFocus.displayRole {
            payload["display_role"] = displayRole.rawValue
        }
        return payload
    }

    func coarseIdleStart(secondsSinceAnyInput: Double) -> [String: String] {
        [
            "level": "coarse",
            "reason": "idle_started",
            "seconds_since_any_input": String(format: "%.1f", secondsSinceAnyInput),
            "summary_trigger": "true"
        ]
    }
}
