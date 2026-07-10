import Foundation
import Testing
@testable import ObserverApp

struct GeminiInsightProviderTests {
    @Test func extractsModelOutputTextFromInteractionsResponse() throws {
        let data = Data("""
        {
          "steps": [
            {
              "type": "model_output",
              "content": [
                {
                  "type": "text",
                  "text": "Текущая задача: проектирование Observer."
                }
              ]
            }
          ]
        }
        """.utf8)

        let insight = try GeminiInsightProvider.extractInsight(from: data)
        #expect(insight == "Текущая задача: проектирование Observer.")
    }

    @Test func promptMentionsUserTriggeredCompactContext() {
        let prompt = GeminiInsightProvider.buildPrompt(
            context: "Context",
            digest: "Digest",
            attention: "Контекст: смотрит на экран"
        )

        #expect(prompt.contains("user-triggered context packet"))
        #expect(prompt.contains("Контекст: смотрит на экран"))
        #expect(prompt.contains("Keep the answer concise"))
    }
}
