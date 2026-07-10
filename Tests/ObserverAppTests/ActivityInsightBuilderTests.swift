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

        #expect(text.contains("Поиск / сравнение"))
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

    @Test func usesMouseDisplayAsWorkspaceSignal() {
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

        #expect(text == "Дизайн: основной экран")
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

        #expect(text == "Защита: похоже, отошел и прикрыл экран")
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

    private func face(
        yaw: Double,
        position: AttentionSnapshot.FacePosition
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
            pitch: nil,
            roll: nil
        )
    }

    private func focus(
        appName: String,
        appID: String,
        displayRole: WorkspaceTopology.DisplayRole? = nil
    ) -> AppFocusSnapshot {
        AppFocusSnapshot(
            appID: appID,
            appName: appName,
            processID: 1,
            windowTitle: nil,
            screenIndex: displayRole == nil ? nil : 0,
            displayRole: displayRole,
            contentAllowed: false
        )
    }
}
