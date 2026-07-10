import Foundation

struct TimelineFormatter {
    func format(events: [ObserverEvent]) -> String {
        let formatter = ISO8601DateFormatter()
        guard !events.isEmpty else {
            return "Observer timeline is empty."
        }

        return events.suffix(120).map { event in
            let app = event.payload["app_name"] ?? event.appID ?? "-"
            let detail = detailText(for: event)
            return "\(formatter.string(from: event.timestamp))  \(event.type.rawValue)  \(app)\n\(detail)"
        }.joined(separator: "\n\n")
    }

    private func detailText(for event: ObserverEvent) -> String {
        switch event.type {
        case .userNote:
            return "  note: \(event.payload["note"] ?? "")"
        case .appFocus:
            return "  content_allowed: \(event.payload["content_allowed"] ?? "unknown")"
        case .appFocusInterval:
            return "  duration: \(event.payload["duration_seconds"] ?? "?")s, reason: \(event.payload["reason"] ?? "-")"
        case .screenContext:
            return "  window: \(event.payload["window_title"] ?? "-")"
        case .ocrContext:
            return "  ocr: \(event.payload["text"] ?? "-")"
        case .attention:
            return "  face: \(event.payload["face_present"] ?? "unknown"), zone: \(event.payload["attention_zone"] ?? "unknown")"
        case .detectorFired, .hintCandidate:
            return "  \(event.payload["interpretation"] ?? event.payload["hint"] ?? event.payloadSummary)"
        case .sessionBoundary:
            return "  boundary: \(event.payload["boundary"] ?? "unknown")"
        case .localSummary:
            return "  summary captured"
        default:
            return "  \(event.payloadSummary)"
        }
    }
}
