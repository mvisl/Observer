import Testing
@testable import ObserverApp

struct GazeCalibrationBuilderTests {
    @Test func usesTypingAsCaretProxy() throws {
        let sample = try #require(GazeCalibrationBuilder().build(
            attention: face(yaw: 0.2),
            input: input(keyboard: 1, mouse: 20, click: 20, mouseRole: .productivity),
            currentFocus: focus(role: .mainWorkbench),
            activityInsight: "Диалог с ИИ: формулирует задачу"
        ))

        #expect(sample.targetSource == "typing_caret_proxy")
        #expect(sample.targetDisplayRole == .mainWorkbench)
        #expect(sample.payload["head_yaw"] == "0.2000")
        #expect(sample.payload["target_assumption"] == "caret_end_if_touch_typing")
    }

    @Test func usesClickAsPointerProxy() throws {
        let sample = try #require(GazeCalibrationBuilder().build(
            attention: face(yaw: -0.1),
            input: input(keyboard: 20, mouse: 1, click: 1, mouseRole: .productivity),
            currentFocus: focus(role: .mainWorkbench),
            activityInsight: nil
        ))

        #expect(sample.targetSource == "mouse_click_proxy")
        #expect(sample.targetDisplayRole == .productivity)
        #expect(sample.payload["target_assumption"] == "clicked_screen_target")
        #expect(sample.payload["pointer_context"] == "screenTarget")
    }

    @Test func ignoresMouseProxyInAbstractPointerContext() {
        let sample = GazeCalibrationBuilder().build(
            attention: face(yaw: 0.1),
            input: input(keyboard: 20, mouse: 0, click: 1, mouseRole: .mainWorkbench),
            currentFocus: AppFocusSnapshot(
                appID: "com.valvesoftware.steam",
                appName: "Steam Game",
                processID: 1,
                windowTitle: "Shooter",
                screenIndex: 0,
                displayRole: .mainWorkbench,
                contentAllowed: false
            ),
            activityInsight: nil
        )

        #expect(sample == nil)
    }

    @Test func ignoresMissingFace() {
        let sample = GazeCalibrationBuilder().build(
            attention: nil,
            input: input(keyboard: 1, mouse: 1, click: 1, mouseRole: .mainWorkbench),
            currentFocus: focus(role: .mainWorkbench),
            activityInsight: nil
        )

        #expect(sample == nil)
    }

    private func face(yaw: Double) -> AttentionSnapshot {
        AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: .right,
            confidence: 0.8,
            faceCount: 1,
            faceCenterX: 0.65,
            faceCenterY: 0.25,
            faceArea: 0.04,
            yaw: yaw,
            pitch: nil,
            roll: nil
        )
    }

    private func input(
        keyboard: Double,
        mouse: Double,
        click: Double,
        mouseRole: WorkspaceTopology.DisplayRole
    ) -> InputActivitySnapshot {
        InputActivitySnapshot(
            secondsSinceKeyboard: keyboard,
            secondsSinceMouseMove: mouse,
            secondsSinceClick: click,
            secondsSinceAnyInput: min(keyboard, mouse, click),
            mouseScreenIndex: 1,
            mouseDisplayRole: mouseRole
        )
    }

    private func focus(role: WorkspaceTopology.DisplayRole) -> AppFocusSnapshot {
        AppFocusSnapshot(
            appID: "com.example.app",
            appName: "Example",
            processID: 1,
            windowTitle: nil,
            screenIndex: 0,
            displayRole: role,
            contentAllowed: true
        )
    }
}
