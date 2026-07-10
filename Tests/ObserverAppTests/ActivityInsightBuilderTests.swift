import Foundation
import Testing
@testable import ObserverApp

struct ActivityInsightBuilderTests {
    @Test func describesActiveFocusBeyondPresence() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0, position: .right),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 2,
                secondsSinceMouseMove: 4,
                secondsSinceClick: 20,
                secondsSinceAnyInput: 2
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "Figma", appID: "com.figma.Desktop"),
            currentFocusStartedAt: Date().addingTimeInterval(-240),
            focusChangesLastMinute: 0
        )

        #expect(text.contains("Дизайн"))
        #expect(text.contains("устойчиво"))
    }

    @Test func describesSearchWhenSwitchingOften() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0, position: .right),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 1,
                secondsSinceMouseMove: 1,
                secondsSinceClick: 1,
                secondsSinceAnyInput: 1
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "Google Chrome", appID: "com.google.Chrome"),
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 5
        )

        #expect(text == "Веб-контекст: переключает вкладки")
    }

    @Test func defaultChromeContextIsNeutralBrowsingNotSearch() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0, position: .right),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 1,
                secondsSinceMouseMove: 1,
                secondsSinceClick: 1,
                secondsSinceAnyInput: 1
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "Google Chrome", appID: "com.google.Chrome"),
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 0
        )

        #expect(text == "Веб-контекст: просматривает страницу")
        #expect(!text.contains("ищет"))
        #expect(!text.contains("сравнивает"))
    }

    @Test func socialNetworkInChromeIsNotSearchAndCompare() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0, position: .right),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 1,
                secondsSinceMouseMove: 1,
                secondsSinceClick: 1,
                secondsSinceAnyInput: 1
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(
                appName: "Google Chrome",
                appID: "com.google.Chrome",
                windowTitle: "Instagram - Google Chrome"
            ),
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 0
        )

        #expect(text == "Соцсети: просматривает ленту")
        #expect(!text.contains("ищет"))
        #expect(!text.contains("сравнивает"))
    }

    @Test func rapidSocialFeedSwitchingIsNotWorkSearch() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0, position: .right),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 1,
                secondsSinceMouseMove: 1,
                secondsSinceClick: 1,
                secondsSinceAnyInput: 1
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(
                appName: "Google Chrome",
                appID: "com.google.Chrome",
                windowTitle: "X / Twitter - Google Chrome"
            ),
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 5
        )

        #expect(text == "Соцсети: быстро переключает ленту")
        #expect(!text.contains("Поиск"))
    }

    @Test func doesNotTreatActiveMissingFaceAsAway() {
        let text = ActivityInsightBuilder().build(
            attention: AttentionSnapshot(
                facePresent: false,
                attentionZone: .offScreen,
                facePosition: .unknown,
                confidence: 0.25,
                faceCount: 0,
                faceCenterX: nil,
                faceCenterY: nil,
                faceArea: nil,
                yaw: nil,
                pitch: nil,
                roll: nil
            ),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 2,
                secondsSinceMouseMove: 2,
                secondsSinceClick: 6,
                secondsSinceAnyInput: 2
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "ChatGPT", appID: "com.openai.codex"),
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 0
        )

        #expect(text.contains("Диалог с ИИ"))
        #expect(!text.contains("отошел"))
        #expect(!text.contains("камера"))
    }

    @Test func avoidsTechnicalCameraDetails() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0, position: .right),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 1,
                secondsSinceMouseMove: 1,
                secondsSinceClick: 3,
                secondsSinceAnyInput: 1
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "ChatGPT", appID: "com.openai.codex"),
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 0
        )

        #expect(text == "Диалог с ИИ: формулирует задачу")
        #expect(!text.contains("камера"))
        #expect(!text.contains("экран"))
    }

    @Test func classifiesFigmaAsDesignWork() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0, position: .center),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 1,
                secondsSinceMouseMove: 1,
                secondsSinceClick: 5,
                secondsSinceAnyInput: 1
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "Figma", appID: "com.figma.Desktop"),
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 0
        )

        #expect(text == "Дизайн: правит макет")
    }

    @Test func avoidsGenericScreenRoleAsInsight() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0, position: .right),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 8,
                secondsSinceMouseMove: 0,
                secondsSinceClick: 4,
                secondsSinceAnyInput: 0,
                mouseScreenIndex: 0,
                mouseDisplayRole: .mainWorkbench
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(
                appName: "Figma",
                appID: "com.figma.Desktop",
                displayRole: .mainWorkbench
            ),
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 0
        )

        #expect(text == "Дизайн: правит макет")
        #expect(!text.contains("основной экран"))
        #expect(!text.contains("рабочий экран"))
    }

    @Test func loginWindowMeansProtectiveAwayState() {
        let text = ActivityInsightBuilder().build(
            attention: AttentionSnapshot(
                facePresent: false,
                attentionZone: .offScreen,
                facePosition: .unknown,
                confidence: 0.3,
                faceCount: 0,
                faceCenterX: nil,
                faceCenterY: nil,
                faceArea: nil,
                yaw: nil,
                pitch: nil,
                roll: nil
            ),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 180,
                secondsSinceMouseMove: 180,
                secondsSinceClick: 180,
                secondsSinceAnyInput: 180
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "loginwindow", appID: "com.apple.loginwindow"),
            currentFocusStartedAt: Date().addingTimeInterval(-180),
            focusChangesLastMinute: 0
        )

        #expect(text == "Защита: отошёл и прикрыл экран")
    }

    @Test func missingFaceAndMediumIdleDoesNotMeanAway() {
        let text = ActivityInsightBuilder().build(
            attention: AttentionSnapshot(
                facePresent: false,
                attentionZone: .offScreen,
                facePosition: .unknown,
                confidence: 0.3,
                faceCount: 0,
                faceCenterX: nil,
                faceCenterY: nil,
                faceArea: nil,
                yaw: nil,
                pitch: nil,
                roll: nil
            ),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 125,
                secondsSinceMouseMove: 125,
                secondsSinceClick: 125,
                secondsSinceAnyInput: 125
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "Figma", appID: "com.figma.Desktop"),
            currentFocusStartedAt: Date().addingTimeInterval(-240),
            focusChangesLastMinute: 0
        )

        #expect(text == "Дизайн: долгая пауза")
        #expect(!text.contains("Отошёл"))
    }

    @Test func missingFaceAndVeryLongIdleStaysInternalWithoutLockScreen() {
        let text = ActivityInsightBuilder().build(
            attention: AttentionSnapshot(
                facePresent: false,
                attentionZone: .offScreen,
                facePosition: .unknown,
                confidence: 0.3,
                faceCount: 0,
                faceCenterX: nil,
                faceCenterY: nil,
                faceArea: nil,
                yaw: nil,
                pitch: nil,
                roll: nil
            ),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 920,
                secondsSinceMouseMove: 920,
                secondsSinceClick: 920,
                secondsSinceAnyInput: 920
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "Figma", appID: "com.figma.Desktop"),
            currentFocusStartedAt: Date().addingTimeInterval(-1_020),
            focusChangesLastMinute: 0
        )

        #expect(text == "Дизайн: долгая пауза")
        #expect(!text.contains("Отошёл"))
    }

    @Test func readingScreenIsNotMicroPauseWhenFaceStaysPresent() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0, position: .right),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 44,
                secondsSinceMouseMove: 44,
                secondsSinceClick: 44,
                secondsSinceAnyInput: 44,
                mouseScreenIndex: 0,
                mouseDisplayRole: .mainWorkbench
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "ChatGPT", appID: "com.openai.codex", displayRole: .mainWorkbench),
            currentFocusStartedAt: Date().addingTimeInterval(-360),
            focusChangesLastMinute: 0
        )

        #expect(text == "Диалог с ИИ: читает ответ: нижняя часть экрана")
        #expect(!text.contains("микропауза"))
    }

    @Test func classifiesLookingAwayIdleAsOffScreenWithoutStrongPhoneEvidence() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0.72, position: .right, pitch: -0.32),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 38,
                secondsSinceMouseMove: 38,
                secondsSinceClick: 38,
                secondsSinceAnyInput: 38
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "ChatGPT", appID: "com.openai.codex", displayRole: .mainWorkbench),
            currentFocusStartedAt: Date().addingTimeInterval(-360),
            focusChangesLastMinute: 0
        )

        #expect(text == "Диалог с ИИ: смотрит вне экрана")
        #expect(!text.contains("внимание ушло"))
        #expect(!text.contains("телефон"))
    }

    @Test func downGazeIdleOnCommunicationAppIsPhoneNotReadingMessages() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0.05, position: .center, pitch: -0.34),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 55,
                secondsSinceMouseMove: 55,
                secondsSinceClick: 55,
                secondsSinceAnyInput: 55
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "Rakuten Viber", appID: "com.viber.osx", displayRole: .communication),
            currentFocusStartedAt: Date().addingTimeInterval(-360),
            focusChangesLastMinute: 0
        )

        #expect(text == "Коммуникация: смотрит в телефон")
        #expect(!text.contains("читает"))
    }

    @Test func downGazeIdleOnFigmaIsPhoneNotInspectingLayout() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0.05, position: .center),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 28,
                secondsSinceMouseMove: 28,
                secondsSinceClick: 28,
                secondsSinceAnyInput: 28
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocus: focus(appName: "Figma", appID: "com.figma.Desktop", displayRole: .mainWorkbench),
            currentFocusStartedAt: Date().addingTimeInterval(-360),
            focusChangesLastMinute: 0
        )

        #expect(text == "Дизайн: рассматривает макет: нижняя часть экрана")
        #expect(!text.contains("телефон"))
    }

    private func face(
        yaw: Double,
        position: AttentionSnapshot.FacePosition,
        pitch: Double? = nil
    ) -> AttentionSnapshot {
        AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: position,
            confidence: 0.8,
            faceCount: 1,
            faceCenterX: 0.68,
            faceCenterY: 0.28,
            faceArea: 0.04,
            yaw: yaw,
            pitch: pitch,
            roll: nil
        )
    }

    private func focus(
        appName: String,
        appID: String,
        displayRole: WorkspaceTopology.DisplayRole? = nil,
        windowTitle: String? = nil
    ) -> AppFocusSnapshot {
        AppFocusSnapshot(
            appID: appID,
            appName: appName,
            processID: 1,
            windowTitle: windowTitle,
            screenIndex: displayRole == nil ? nil : 0,
            displayRole: displayRole,
            contentAllowed: false
        )
    }
}
