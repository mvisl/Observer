import Foundation

struct PredictionBuilder {
    func build(events: [ObserverEvent]) -> [String: String] {
        let recent = events.suffix(120)
        let latestState = recent.last { $0.type == .cognitiveState }?.payload["state"] ?? "unknown"
        let latestInput = recent.last { $0.type == .inputActivity }
        let idle = Double(latestInput?.payload["seconds_since_any_input"] ?? "") ?? 0
        let recentSwitches = recent.filter { $0.type == .appFocus }.count
        let recentCues = recent.filter { $0.type == .behaviorCue || $0.type == .boundReaction }.count

        let stuckProbability = min(0.95, 0.10 + (idle > 60 ? 0.25 : 0) + (recentSwitches >= 6 ? 0.25 : 0) + (recentCues >= 2 ? 0.20 : 0))
        let flowEndProbability: Double
        if latestState == "flow" {
            flowEndProbability = min(0.9, 0.15 + (idle > 20 ? 0.35 : 0) + (recentSwitches > 0 ? 0.25 : 0))
        } else {
            flowEndProbability = 0.0
        }

        return [
            "prediction_kind": "shadow_cognitive",
            "p_stuck_20m": String(format: "%.3f", stuckProbability),
            "p_flow_end_10m": String(format: "%.3f", flowEndProbability),
            "latest_state": latestState,
            "seconds_since_any_input": String(format: "%.1f", idle),
            "recent_focus_switches": "\(recentSwitches)",
            "recent_cue_count": "\(recentCues)",
            "shadow_mode": "true"
        ]
    }
}
