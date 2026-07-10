import Foundation

struct DiagnosticsBuilder {
    func build(
        dataDirectory: URL,
        topology: WorkspaceTopology,
        settings: ObserverSettings,
        eventCounts: [String: Int],
        currentFocus: AppFocusSnapshot?,
        latestAttention: AttentionSnapshot?,
        permissions: PermissionAdvisor.Status,
        mode: ObserverController.Mode
    ) -> String {
        let counts = eventCounts
            .sorted { $0.key < $1.key }
            .map { "- \($0.key): \($0.value)" }
            .joined(separator: "\n")

        return """
        # Observer Diagnostics

        Mode: \(mode.displayText)
        Data directory: \(dataDirectory.path)

        ## Workspace

        \(topology.markdownDescription)

        ## Settings

        - Summary interval: \(Int(settings.summaryIntervalSeconds))s
        - Retention: \(settings.retentionDays)d
        - Idle session boundary: \(Int(settings.idleSessionBoundarySeconds))s
        - Start observing on launch: \(settings.startObservingOnLaunch)
        - Start camera attention on launch: \(settings.startCameraAttentionOnLaunch)
        - Hint delivery mode: \(settings.hintDeliveryMode)
        - Minimum hint interval: \(Int(settings.minimumHintIntervalSeconds))s
        - Attention sample interval: \(Int(settings.attentionSampleIntervalSeconds))s
        - Screen context refresh: \(Int(settings.screenContextRefreshSeconds))s
        - Frequent switch threshold: \(settings.detectorSettings.frequentSwitchFocusEvents) focus events
        - Reading pause threshold: \(Int(settings.detectorSettings.readingPauseSeconds))s

        ## Current Focus

        \(describeFocus(currentFocus))

        ## Attention

        \(latestAttention?.displayText ?? "No camera attention sample.")

        ## Permissions

        - Accessibility: \(permissions.accessibility)
        - Camera: \(permissions.camera)
        - Screen Recording: \(permissions.screenRecording)

        ## Event Counts

        \(counts.isEmpty ? "- No events." : counts)
        """
    }

    private func describeFocus(_ focus: AppFocusSnapshot?) -> String {
        guard let focus else {
            return "- No focus snapshot."
        }

        return [
            "- App: \(focus.appName)",
            "- App ID: \(focus.appID ?? "unknown")",
            "- Content allowed: \(focus.contentAllowed)",
            "- Display role: \(focus.displayRole?.rawValue ?? "unknown")"
        ].joined(separator: "\n")
    }
}
