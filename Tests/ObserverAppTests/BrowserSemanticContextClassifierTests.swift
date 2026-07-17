import Foundation
import Testing
@testable import ObserverApp

struct BrowserSemanticContextClassifierTests {
    @Test func chromeWhatsAppMessageIsCommunicationNotResearch() {
        let event = event(
            payload: [
                "content_kind": "message",
                "resource_domain": "web.whatsapp.com",
                "topic": "personal conversation"
            ]
        )

        #expect(BrowserSemanticContextClassifier.isCommunication(event))
        #expect(!BrowserSemanticContextClassifier.supportsResearchFallback(event))
    }

    @Test func articleCanSupportResearchFallback() {
        let event = event(
            payload: [
                "content_kind": "article",
                "resource_domain": "example.com"
            ]
        )

        #expect(!BrowserSemanticContextClassifier.isCommunication(event))
        #expect(BrowserSemanticContextClassifier.supportsResearchFallback(event))
    }

    private func event(payload: [String: String]) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: Date(),
            type: .contentContext,
            source: "test",
            platform: "macOS",
            displayRole: .productivity,
            appID: "com.google.Chrome",
            confidence: 1,
            payload: payload,
            workspaceTopologyVersion: 1
        )
    }
}
