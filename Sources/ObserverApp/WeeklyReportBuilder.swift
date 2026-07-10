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
