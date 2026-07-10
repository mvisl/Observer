import Foundation

struct ResearchDigestBuilder {
    func build(events: [ObserverEvent]) -> String {
        let formatter = ISO8601DateFormatter()
        let summaries = events.filter { $0.type == .localSummary }.suffix(3)
        let detectors = events.filter { $0.type == .detectorFired }.suffix(8)
        let hints = events.filter { $0.type == .hintCandidate }.suffix(8)
        let notes = events.filter { $0.type == .userNote }.suffix(8)

        return """
        # Observer Research Digest

        Generated: \(formatter.string(from: Date()))

        ## Recent Summaries

        \(formatSummaries(summaries))

        ## Patterns

        \(formatDetectors(detectors))

        ## Quiet Hint Candidates

        \(formatHints(hints))

        ## User Notes

        \(formatNotes(notes))

        ## Next Investigation

        \(nextInvestigation(detectors: Array(detectors), hints: Array(hints), notes: Array(notes)))
        """
    }

    private func formatSummaries(_ summaries: ArraySlice<ObserverEvent>) -> String {
        guard !summaries.isEmpty else {
            return "- No summaries yet."
        }

        return summaries.map { event in
            "- \(event.payload["summary"]?.prefix(700) ?? "")"
        }.joined(separator: "\n\n")
    }

    private func formatDetectors(_ detectors: ArraySlice<ObserverEvent>) -> String {
        guard !detectors.isEmpty else {
            return "- No detector patterns yet."
        }

        return detectors.map { event in
            "- \(event.payload["detector"] ?? "unknown"): \(event.payload["interpretation"] ?? "")"
        }.joined(separator: "\n")
    }

    private func formatHints(_ hints: ArraySlice<ObserverEvent>) -> String {
        guard !hints.isEmpty else {
            return "- No quiet hints queued."
        }

        return hints.map { event in
            "- \(event.payload["hint"] ?? "")"
        }.joined(separator: "\n")
    }

    private func formatNotes(_ notes: ArraySlice<ObserverEvent>) -> String {
        guard !notes.isEmpty else {
            return "- No user notes."
        }

        return notes.map { event in
            "- \(event.payload["note"] ?? "")"
        }.joined(separator: "\n")
    }

    private func nextInvestigation(
        detectors: [ObserverEvent],
        hints: [ObserverEvent],
        notes: [ObserverEvent]
    ) -> String {
        if !notes.isEmpty {
            return "- Use the latest user notes as ground truth before interpreting behavior."
        }
        if detectors.contains(where: { $0.payload["detector"] == "frequent_app_switching" }) {
            return "- Investigate whether frequent switching is useful comparison work or lost context."
        }
        if hints.isEmpty {
            return "- Keep observing quietly until stronger patterns appear."
        }
        return "- Review hint candidates and promote only the ones that repeatedly help."
    }
}
