import Testing
@testable import ObserverApp

struct TextAffectCueBuilderTests {
    @Test func detectsFrustratedWritingTone() throws {
        let cue = try #require(TextAffectCueBuilder().build(
            text: "хуета. Ничего не помог. Это СТРОГО ЗАПРЕЩЕНО МОИМИ ПРАВИЛАМИ!!!",
            appName: "ChatGPT",
            activityInsight: "Диалог с ИИ: основной экран"
        ))

        #expect(cue.name == "frustration_candidate")
        #expect(cue.payload["interpretation"] == "frustrated_writing_tone")
        #expect(cue.payload["markers"]?.contains("strong_negative_language") == true)
        #expect(cue.confidence >= 0.7)
    }

    @Test func ignoresNeutralWriting() {
        let cue = TextAffectCueBuilder().build(
            text: "Делаю новую карточку с прогресс-баром",
            appName: "Figma",
            activityInsight: nil
        )

        #expect(cue == nil)
    }

    @Test func ignoresUppercaseWithoutNegativeContext() {
        let cue = TextAffectCueBuilder().build(
            text: "GOOGLE CHROME TELEGRAM WHATSAPP FIGMA LIBERTEX ASK GEMINI",
            appName: "Google Chrome",
            activityInsight: "Веб-контекст: основной экран"
        )

        #expect(cue == nil)
    }

    @Test func detectsVisualDesignCause() throws {
        let cue = try #require(TextAffectCueBuilder().build(
            text: "злюсь, потому что смотрю на дизайн и вижу абсолютную какафонию",
            appName: "Figma",
            activityInsight: "Дизайн: рассматривает макет"
        ))

        #expect(cue.payload["likely_cause"] == "visual_design_cacophony")
        #expect(cue.insight.contains("визуального хаоса"))
    }
}
