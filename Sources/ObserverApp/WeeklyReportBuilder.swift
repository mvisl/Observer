import Foundation

struct WeeklyReportBuilder {
    func build(
        events: [ObserverEvent],
        baselines: [PersonalBaselineSample],
        patterns: [SequencePattern],
        calendarDays: [ObservationCalendarDay] = []
    ) -> String {
        """
        # Observer Weekly Report

        ## Coverage

        \(coverage(calendarDays))

        ## Energy Curve

        \(energyCurve(baselines))

        ## Cognitive States

        \(stateDistribution(events))

        ## Sequence Patterns

        \(patterns.prefix(8).map { "- \($0.antecedentChain.joined(separator: " -> ")) => \($0.outcome), support \($0.support), confidence \($0.confidenceStat)" }.joined(separator: "\n").ifEmpty("- No validated patterns yet."))

        ## Predictor

        \(predictionSummary(events))

        ## Readiness

        \(readinessSummary(events))

        ## Funnel

        \(funnelSummary(events))

        ## Experiments

        - No active N-of-1 experiments. New experiments require manual activation.

        ## Top Insights

        \(topInsights(events))

        Note: report language must stay behavioral, for example "after X tempo drops", not diagnostic.
        """
    }

    private func coverage(_ days: [ObservationCalendarDay]) -> String {
        guard !days.isEmpty else {
            return "- Coverage data is not available yet."
        }
        let plannedHours = days.reduce(0) { $0 + $1.plannedSeconds / 3600 }
        let observedHours = days.reduce(0) { $0 + $1.observedSeconds / 3600 }
        let ratio = plannedHours > 0 ? observedHours / plannedHours : 0
        let reliability: String
        if ratio >= 0.8 {
            reliability = "high"
        } else if ratio >= 0.5 {
            reliability = "medium"
        } else {
            reliability = "low"
        }
        let missing = days
            .filter { $0.coverageRatio < 0.75 || $0.offReason != "none" }
            .map { "- \($0.date): \($0.offReason), coverage \(Int($0.coverageRatio * 100))%" }
            .joined(separator: "\n")
        return """
        - Observed \(String(format: "%.1f", observedHours))h / planned \(String(format: "%.1f", plannedHours))h (\(Int(ratio * 100))%).
        - Reliability: \(reliability).
        \(missing.isEmpty ? "- No major coverage gaps." : missing)
        """
    }

    private func energyCurve(_ baselines: [PersonalBaselineSample]) -> String {
        let input = baselines.filter { $0.metric == "input_tempo_proxy" }
        guard !input.isEmpty else {
            return "- No input tempo baseline yet."
        }
        return input.sorted { $0.hour < $1.hour }
            .map { "- hour \($0.hour): \(String(format: "%.3f", $0.value))" }
            .joined(separator: "\n")
    }

    private func stateDistribution(_ events: [ObserverEvent]) -> String {
        let counts = events
            .filter { $0.type == .cognitiveState }
            .reduce(into: [String: Int]()) { result, event in
                result[event.payload["state"] ?? "unknown", default: 0] += 1
            }
        guard !counts.isEmpty else {
            return "- No cognitive state events yet."
        }
        return counts.sorted { $0.key < $1.key }
            .map { "- \($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    private func predictionSummary(_ events: [ObserverEvent]) -> String {
        let predictions = events.filter { $0.type == .prediction }
        guard let latest = predictions.last else {
            return "- No prediction events yet."
        }
        return "- Latest shadow prediction: stuck \(latest.payload["p_stuck_20m"] ?? "?"), flow-end \(latest.payload["p_flow_end_10m"] ?? "?")."
    }

    private func readinessSummary(_ events: [ObserverEvent]) -> String {
        guard let latest = events.last(where: { $0.type == .readinessReport }) else {
            return "- No readiness report yet."
        }
        let status = latest.payload["status"] ?? "unknown"
        let blockers = latest.payload["blockers"].flatMap { $0.isEmpty ? nil : $0 } ?? "none"
        return """
        - Status: \(status).
        - Blockers: \(blockers).
        """
    }

    private func funnelSummary(_ events: [ObserverEvent]) -> String {
        guard let latest = events.last(where: { $0.type == .funnelReport }) else {
            return "- No funnel report yet."
        }
        return """
        | Stage | Today | 7d |
        | --- | ---: | ---: |
        | Signals | \(latest.payload["today_signals"] ?? "0") | \(latest.payload["rolling_7d_signals"] ?? "0") |
        | Behavior cues | \(latest.payload["today_behavior_cues"] ?? "0") | \(latest.payload["rolling_7d_behavior_cues"] ?? "0") |
        | Fusion hypotheses | \(latest.payload["today_fusion_hypotheses"] ?? "0") | \(latest.payload["rolling_7d_fusion_hypotheses"] ?? "0") |
        | Cognitive states | \(latest.payload["today_cognitive_states"] ?? "0") | \(latest.payload["rolling_7d_cognitive_states"] ?? "0") |
        | Episode outcomes | \(latest.payload["today_episode_outcomes"] ?? "0") | \(latest.payload["rolling_7d_episode_outcomes"] ?? "0") |
        | Bound reactions | \(latest.payload["today_bound_reactions"] ?? "0") | \(latest.payload["rolling_7d_bound_reactions"] ?? "0") |
        """
    }

    private func topInsights(_ events: [ObserverEvent]) -> String {
        let reactions = events.filter { $0.type == .boundReaction }.suffix(3)
        guard !reactions.isEmpty else {
            return "- Not enough bound reactions yet."
        }
        return reactions.map { event in
            let topic = event.payload["topic"] ?? "unknown"
            let cue = event.payload["cue"] ?? "reaction"
            return "- After \(topic): \(cue)"
        }.joined(separator: "\n")
    }
}
