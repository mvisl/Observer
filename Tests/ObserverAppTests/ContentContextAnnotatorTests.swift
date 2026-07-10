import Foundation
import Testing
@testable import ObserverApp

struct ContentContextAnnotatorTests {
    @Test func annotatesMessageWithoutRawFragmentByDefault() {
        let context = ScreenContextSnapshot(
            appID: "net.whatsapp.WhatsApp",
            appName: "WhatsApp",
            windowTitle: "Anna",
            windowRole: nil,
            document: nil,
            focusedElementRole: nil,
            focusedElementTitle: nil,
            focusedElementValue: "Спасибо, классная новость",
            selectedText: nil,
            screenIndex: nil,
            displayRole: nil,
            confidence: 0.8
        )

        let annotation = ContentContextAnnotator().annotate(context: context, allowRawKinds: [])

        #expect(annotation?.contentKind == "message")
        #expect(annotation?.sourceEntityDisplayName == "Anna")
        #expect(annotation?.sentiment == "pos")
        #expect(annotation?.language == "ru")
        #expect(annotation?.rawFragment == nil)
    }

    @Test func permitsRawFragmentForPromptKindOnlyWhenConfigured() {
        let context = ScreenContextSnapshot(
            appID: "com.openai.chat",
            appName: "ChatGPT",
            windowTitle: "ChatGPT",
            windowRole: nil,
            document: nil,
            focusedElementRole: nil,
            focusedElementTitle: nil,
            focusedElementValue: "Сделай новый прогресс бар",
            selectedText: nil,
            screenIndex: nil,
            displayRole: nil,
            confidence: 0.8
        )

        let annotation = ContentContextAnnotator().annotate(context: context, allowRawKinds: ["prompt"])

        #expect(annotation?.contentKind == "prompt")
        #expect(annotation?.rawFragment?.contains("прогресс") == true)
    }
}
