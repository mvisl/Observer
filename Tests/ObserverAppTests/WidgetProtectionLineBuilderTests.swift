import Testing
@testable import ObserverApp

struct WidgetProtectionLineBuilderTests {
    @Test func securityAgentWithMissingFaceOverridesWorkContext() {
        let line = WidgetProtectionLineBuilder().build(
            appName: "SecurityAgent",
            appID: "com.apple.SecurityAgent",
            facePresent: false,
            missingFaceSamples: 1,
            secondsSinceAnyInput: 42
        )

        #expect(line == "Защита: экран закрыт; тебя нет у компьютера")
    }

    @Test func loginWindowWithFacePresentDoesNotClaimAway() {
        let line = WidgetProtectionLineBuilder().build(
            appName: "loginwindow",
            appID: "com.apple.loginwindow",
            facePresent: true,
            missingFaceSamples: 0,
            secondsSinceAnyInput: 3
        )

        #expect(line == "Защита: системный экран поверх работы")
    }

    @Test func confirmedMissingFaceShowsAwayWithoutMaybe() {
        let line = WidgetProtectionLineBuilder().build(
            appName: "Google Chrome",
            appID: "com.google.Chrome",
            facePresent: false,
            missingFaceSamples: 3,
            secondsSinceAnyInput: 30
        )

        #expect(line == "Защита: тебя нет у компьютера; рабочий контекст сохранён")
    }

    @Test func transientFaceLossWhileInputActiveDoesNotCallAway() {
        let line = WidgetProtectionLineBuilder().build(
            appName: "Google Chrome",
            appID: "com.google.Chrome",
            facePresent: false,
            missingFaceSamples: 1,
            secondsSinceAnyInput: 2
        )

        #expect(line == "Защита: камера потеряла лицо, но ввод ещё активен")
    }
}
