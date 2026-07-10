import Foundation
import Testing
@testable import ObserverApp

struct DiagnosticsBuilderTests {
    @Test func includesSettingsAndEventCounts() {
        let diagnostics = DiagnosticsBuilder().build(
            dataDirectory: URL(filePath: "/tmp/observer"),
            topology: .defaultTwoDisplaySetup,
            settings: .defaults,
            eventCounts: ["appFocus": 2],
            currentFocus: nil,
            latestAttention: nil,
            permissions: PermissionAdvisor.Status(
                accessibility: true,
                camera: "authorized",
                screenRecording: true
            ),
            mode: .paused,
            hasGeminiAPIKey: true
        )

        #expect(diagnostics.contains("## Settings"))
        #expect(diagnostics.contains("## Permissions"))
        #expect(diagnostics.contains("Gemini key configured: true"))
        #expect(diagnostics.contains("appFocus: 2"))
    }
}
