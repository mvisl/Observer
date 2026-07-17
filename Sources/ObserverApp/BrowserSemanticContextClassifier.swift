import Foundation

enum BrowserSemanticContextClassifier {
    private static let communicationMarkers = [
        "whatsapp", "telegram", "viber", "messenger", "slack", "discord", "mail.google"
    ]

    private static let researchKinds: Set<String> = ["article", "doc", "feed", "video"]

    static func isCommunication(_ event: ObserverEvent) -> Bool {
        if ["message", "email"].contains(event.payload["content_kind"] ?? "") {
            return true
        }

        let transport = [
            event.payload["resource_domain"],
            event.payload["url_host"],
            event.payload["resource_url"],
            event.payload["source_entity_display_name"],
            event.payload["entity_name"]
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return communicationMarkers.contains { transport.contains($0) }
    }

    static func supportsResearchFallback(_ event: ObserverEvent) -> Bool {
        !isCommunication(event)
            && researchKinds.contains(event.payload["content_kind"] ?? "")
    }
}
