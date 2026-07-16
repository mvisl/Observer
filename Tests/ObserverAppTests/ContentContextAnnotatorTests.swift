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

    @Test func telegramInChromeBeatsAITabAndAtSignNoise() {
        let context = ScreenContextSnapshot(
            appID: "com.google.Chrome",
            appName: "Google Chrome",
            windowTitle: "Google Trar x Inbox - viac -> web.telegram.org/k/#@Stas6012",
            windowRole: nil,
            document: "https://web.telegram.org/k/#@Stas6012",
            focusedElementRole: nil,
            focusedElementTitle: nil,
            focusedElementValue: "ChatGPT Gemini Telegram Станислав Гжебовский хакатон бесполезно потраченное время задача ради задачи",
            selectedText: nil,
            screenIndex: nil,
            displayRole: nil,
            confidence: 0.8
        )

        let annotation = ContentContextAnnotator().annotate(context: context, allowRawKinds: [])

        #expect(annotation?.contentKind == "message")
        #expect(annotation?.topic == "хакатон: роль, польза и ощущение бессмысленности")
    }

    @Test func classifiesGoogleChatInChromeAsMessage() {
        let context = ScreenContextSnapshot(
            appID: "com.google.Chrome",
            appName: "Google Chrome",
            windowTitle: "Team review - Google Chat",
            windowRole: nil,
            document: "https://chat.google.com/room/AAAA",
            focusedElementRole: nil,
            focusedElementTitle: nil,
            focusedElementValue: "Это не работает, давай переделаем решение",
            selectedText: nil,
            screenIndex: nil,
            displayRole: nil,
            confidence: 0.8
        )

        let annotation = ContentContextAnnotator().annotate(context: context, allowRawKinds: [])

        #expect(annotation?.contentKind == "message")
        #expect(annotation?.topic == "обсуждение сбоя или неверного результата")
        #expect(annotation?.rawFragment == nil)
    }

    @Test func classifiesMeetCaptionsAsMeetingContext() {
        let context = ScreenContextSnapshot(
            appID: "com.google.Chrome",
            appName: "Google Chrome",
            windowTitle: "Weekly Sync - Google Meet",
            windowRole: nil,
            document: "https://meet.google.com/abc-defg-hij",
            focusedElementRole: nil,
            focusedElementTitle: "Captions",
            focusedElementValue: "Captions Андрей says let's review onboarding flow",
            selectedText: nil,
            screenIndex: nil,
            displayRole: nil,
            confidence: 0.8
        )

        let annotation = ContentContextAnnotator().annotate(context: context, allowRawKinds: [])

        #expect(annotation?.contentKind == "meeting_captions")
        #expect(annotation?.rawFragment == nil)
    }

    @Test func classifiesCommunicatorCallAsCallDistilledContext() {
        let context = ScreenContextSnapshot(
            appID: "com.viber",
            appName: "Rakuten Viber",
            windowTitle: "Mother - audio call",
            windowRole: nil,
            document: nil,
            focusedElementRole: nil,
            focusedElementTitle: nil,
            focusedElementValue: "Call in progress",
            selectedText: nil,
            screenIndex: nil,
            displayRole: nil,
            confidence: 0.8
        )

        let annotation = ContentContextAnnotator().annotate(context: context, allowRawKinds: [])

        #expect(annotation?.contentKind == "call_distilled")
        #expect(annotation?.sourceEntityDisplayName?.contains("Mother") == true)
        #expect(annotation?.rawFragment == nil)
    }
}
