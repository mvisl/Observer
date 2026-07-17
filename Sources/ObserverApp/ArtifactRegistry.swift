import Foundation

/// The registry is the single place where aliases collapse into one material.
/// It is intentionally local: it keeps navigation links, not page contents.
struct ArtifactRegistry {
    struct Entry: Hashable {
        let canonicalKey: String
        let kind: String
        let title: String
        let aliases: [String]
        let directLink: String?
        let lastUsedAt: Date
        let confidence: Double
        let evidenceEventIds: [String]
    }

    func entries(from artifacts: [ObserverEvent]) -> [Entry] {
        let grouped = Dictionary(grouping: artifacts) { artifact in
            canonicalKey(for: artifact)
        }
        return grouped.compactMap { key, matches in
            guard !key.isEmpty else { return nil }
            let ordered = matches.sorted { $0.timestamp > $1.timestamp }
            guard let newest = ordered.first else { return nil }
            let displayNames = ordered.compactMap { safeTitle($0.payload["display_name"]) }
            let title = displayNames.max(by: { $0.count < $1.count })
                ?? safeTitle(newest.payload["source_app"])
                ?? "Linked material"
            let aliases = Array(Set(displayNames.filter { $0 != title })).sorted()
            let evidence = Array(Set(ordered.flatMap { eventIDs($0.payload["source_event_ids"]) + [$0.id.uuidString] })).sorted()
            return Entry(
                canonicalKey: key,
                kind: newest.payload["kind"] ?? "unknown",
                title: title,
                aliases: aliases,
                directLink: ordered.compactMap { nonEmpty($0.payload["resource_url"]) }.first,
                lastUsedAt: ordered.map(\.timestamp).max() ?? newest.timestamp,
                confidence: ordered.map(\.confidence).max() ?? newest.confidence,
                evidenceEventIds: evidence
            )
        }.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    private func canonicalKey(for artifact: ObserverEvent) -> String {
        if let canonical = nonEmpty(artifact.payload["canonical_key"]) { return canonical }
        if let link = nonEmpty(artifact.payload["resource_url"]) { return "url:\(normalized(link))" }
        if let title = safeTitle(artifact.payload["display_name"]) {
            return "fallback:\(artifact.payload["kind"] ?? "unknown"):\(normalized(title))"
        }
        return ""
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func safeTitle(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        return value.count > 140 ? String(value.prefix(140)) : value
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func eventIDs(_ value: String?) -> [String] {
        (value ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
