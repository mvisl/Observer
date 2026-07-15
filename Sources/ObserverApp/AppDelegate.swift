import AppKit
import Foundation

@MainActor
final class ObserverApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var controller: ObserverController?
    private var widgetController: WidgetPanelController?
    private var timelineController: TimelineWindowController?
    private var cameraPermissionTimer: Timer?
    private var dashboardServer: DashboardHTTPServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureApplicationIcon()

        do {
            let environment = try AppEnvironment.bootstrap()
            controller = ObserverController(environment: environment)
            if environment.settings.dashboard.enabled {
                let server = DashboardHTTPServer(environment: environment)
                dashboardServer = server
                try server.start()
            }
            controller?.onStateChanged = { [weak self] snapshot in
                self?.widgetController?.update(snapshot)
            }
            configureStatusItem()
            configureWidget()
            controller?.recordLaunch()
            startConfiguredServices()
            startPermissionReconciliation()
            runDeveloperAutomationIfRequested()
        } catch {
            presentStartupFailure(error)
        }
    }

    private func configureApplicationIcon() {
        if let url = Bundle.main.url(forResource: "ObserverIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        } else if let url = Bundle.main.url(forResource: "ObserverStatus", withExtension: "png"),
                  let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusItemIcon(item)
        item.menu = makeMenu()
        statusItem = item
    }

    private func configureStatusItemIcon(_ item: NSStatusItem) {
        if let url = Bundle.main.url(forResource: "ObserverStatus", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
        } else {
            item.button?.title = "O"
        }
        item.button?.toolTip = "Observer: Paused"
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        addItem("Start Observing", #selector(startObserving), to: menu)
        addItem("Pause", #selector(pauseObserving), to: menu)
        addItem("Observe +1h", #selector(observeOneMoreHour), to: menu)
        addItem("Observe +2h", #selector(observeTwoMoreHours), to: menu)
        addItem("Start Camera Attention", #selector(startCameraAttention), to: menu)
        addItem("Stop Camera Attention", #selector(stopCameraAttention), to: menu)
        menu.addItem(.separator())
        addItem("Show Widget", #selector(showWidget), to: menu)
        addItem("Hide Widget", #selector(hideWidget), to: menu)
        addItem("Reset Widget Position", #selector(resetWidgetPosition), to: menu)
        menu.addItem(.separator())
        addItem("Collect Context", #selector(collectContext), to: menu)
        addItem("Generate Local Summary", #selector(generateLocalSummary), to: menu)
        addItem("Generate Research Digest", #selector(generateResearchDigest), to: menu)
        addItem("Export Context File", #selector(exportContextFile), to: menu)
        addItem("Export Research Digest", #selector(exportResearchDigest), to: menu)
        addItem("Export Readiness Report", #selector(exportReadinessReport), to: menu)
        addItem("Export Causal Understanding Report", #selector(exportCausalUnderstandingReport), to: menu)
        addItem("Export Daily Activity Report", #selector(exportDailyActivityReport), to: menu)
        addItem("Export Events JSONL", #selector(exportEventsJSONL), to: menu)
        addItem("Generate Local LLM Insight", #selector(generateLocalLLMInsight), to: menu)
        addItem("Set Gemini API Key", #selector(setGeminiAPIKey), to: menu)
        addItem("Delete Gemini API Key", #selector(deleteGeminiAPIKey), to: menu)
        addItem("Generate Gemini Insight", #selector(generateGeminiInsight), to: menu)
        addItem("Show Timeline", #selector(showTimeline), to: menu)
        addItem("Open Web Dashboard", #selector(openWebDashboard), to: menu)
        addItem("Copy Dashboard Pairing Code", #selector(copyDashboardPairingCode), to: menu)
        addItem("Copy Tailscale Serve Command", #selector(copyTailscaleServeCommand), to: menu)
        addItem("Add Note", #selector(addNote), to: menu)
        addItem("Copy Diagnostics", #selector(copyDiagnostics), to: menu)
        addItem("Capture OCR For Current App", #selector(captureOCRForCurrentApp), to: menu)
        addItem("Allow Current App Context", #selector(allowCurrentAppContext), to: menu)
        addItem("Private: Exclude Current App", #selector(excludeCurrentApp), to: menu)
        addItem("Delete Last Hour", #selector(deleteLastHour), to: menu)
        addItem("Reset Local Memory", #selector(resetLocalMemory), to: menu)
        addItem("Request Accessibility Access", #selector(requestAccessibilityAccess), to: menu)
        addItem("Request Camera Access", #selector(requestCameraAccess), to: menu)
        addItem("Open Camera Privacy Settings", #selector(openCameraPrivacySettings), to: menu)
        addItem("Request Screen Recording Access", #selector(requestScreenRecordingAccess), to: menu)
        addItem("Current Setup", #selector(printCurrentSetup), to: menu)
        addItem("Open Data Folder", #selector(openDataFolder), to: menu)
        addItem("Open Settings File", #selector(openSettingsFile), to: menu)
        addItem("Open Privacy File", #selector(openPrivacyFile), to: menu)
        addItem("Open Exports Folder", #selector(openExportsFolder), to: menu)
        menu.addItem(.separator())
        addItem("Quit", #selector(quit), to: menu, key: "q")
        return menu
    }

    private func addItem(_ title: String, _ action: Selector, to menu: NSMenu, key: String = "") {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
    }

    private func configureWidget() {
        let widget = WidgetPanelController(
            onInsightRequest: { [weak self] interval in
                self?.controller?.localInsight(forLast: interval)
            },
            onInsightOpened: { [weak self] in
                self?.controller?.markSecurityIncidentsSeen()
            },
            onSecurityArtifactRequest: { [weak self] in
                self?.controller?.latestSecurityIncidentArtifactURL()
            },
            onCalibrationSample: { [weak self] displayIndex, cellIndex, predictedDisplayIndex, predictedCellIndex in
                self?.controller?.recordManualGazeCalibration(
                    displayIndex: displayIndex,
                    cellIndex: cellIndex,
                    predictedDisplayIndex: predictedDisplayIndex,
                    predictedCellIndex: predictedCellIndex
                )
            },
            onCalibrationAction: { [weak self] action in
                self?.controller?.recordCalibrationSessionAction(action)
            },
            onExitRequest: { [weak self] in
                self?.quit()
            }
        )
        widgetController = widget
        widget.show()
        if let snapshot = controller?.stateSnapshot {
            widget.update(snapshot)
        }
    }

    @objc private func startObserving() {
        controller?.startObserving()
        statusItem?.button?.toolTip = "Observer: Watching"
    }

    @objc private func pauseObserving() {
        controller?.pauseObserving()
        statusItem?.button?.toolTip = "Observer: Paused"
    }

    @objc private func observeOneMoreHour() {
        controller?.extendObservation(hours: 1)
        statusItem?.button?.toolTip = "Observer: Watching"
    }

    @objc private func observeTwoMoreHours() {
        controller?.extendObservation(hours: 2)
        statusItem?.button?.toolTip = "Observer: Watching"
    }

    @objc private func startCameraAttention() {
        controller?.startCameraAttention()
    }

    @objc private func stopCameraAttention() {
        controller?.stopCameraAttention()
    }

    @objc private func collectContext() {
        guard let context = controller?.collectContextPack() else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(context, forType: .string)
        print(context)
    }

    @objc private func generateLocalSummary() {
        guard let summary = controller?.generateLocalSummary() else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        print(summary)
    }

    @objc private func generateResearchDigest() {
        guard let digest = controller?.generateResearchDigest() else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(digest, forType: .string)
        print(digest)
    }

    @objc private func exportContextFile() {
        guard let url = controller?.exportContextFile() else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func exportResearchDigest() {
        guard let url = controller?.exportResearchDigest() else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func exportReadinessReport() {
        guard let url = controller?.exportReadinessReport() else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func exportCausalUnderstandingReport() {
        guard let url = controller?.exportCausalUnderstandingReport() else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func exportDailyActivityReport() {
        guard let url = controller?.exportDailyActivityReport() else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func exportEventsJSONL() {
        guard let url = controller?.exportEventsJSONL() else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func generateLocalLLMInsight() {
        controller?.generateLocalLLMInsight()
    }

    @objc private func setGeminiAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Set Gemini API Key"
        alert.informativeText = "Observer stores the key in macOS Keychain. It is not written to settings, logs, exports, or the event database."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        input.placeholderString = "Paste Gemini API key"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        controller?.setGeminiAPIKey(input.stringValue)
    }

    @objc private func deleteGeminiAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Delete the Gemini API key from Keychain?"
        alert.informativeText = "Observer will stop using Gemini until a new key is saved."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        controller?.deleteGeminiAPIKey()
    }

    @objc private func generateGeminiInsight() {
        controller?.generateGeminiInsight()
    }

    @objc private func showTimeline() {
        guard let controller else {
            return
        }

        let timeline = timelineController ?? TimelineWindowController()
        timelineController = timeline
        timeline.show(text: controller.timelineText())
    }

    @objc private func openWebDashboard() {
        guard let dashboardServer else {
            return
        }
        NSWorkspace.shared.open(dashboardServer.baseURL)
    }

    @objc private func copyDashboardPairingCode() {
        guard let dashboardServer else {
            return
        }
        let code = dashboardServer.currentPairingCode()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        print("Observer Dashboard pairing code: \(code)")
    }

    @objc private func copyTailscaleServeCommand() {
        let port = controller?.settings.dashboard.port ?? 43127
        let command = """
        tailscale serve localhost:\(port)
        tailscale serve status --json
        # Funnel is intentionally not used for Observer v0.
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        print(command)
    }

    @objc private func addNote() {
        let alert = NSAlert()
        alert.messageText = "Add Observer Note"
        alert.informativeText = "This note is stored locally with the current workspace context."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        input.placeholderString = "What should Observer remember?"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        controller?.addUserNote(input.stringValue)
    }

    @objc private func copyDiagnostics() {
        guard let diagnostics = controller?.copyDiagnostics() else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        print(diagnostics)
    }

    @objc private func captureOCRForCurrentApp() {
        controller?.captureOCRForCurrentApp()
    }

    @objc private func excludeCurrentApp() {
        controller?.excludeCurrentApp()
    }

    @objc private func allowCurrentAppContext() {
        controller?.allowCurrentAppContext()
    }

    @objc private func deleteLastHour() {
        guard confirmDestructiveAction(message: "Delete Observer events from the last hour?") else {
            return
        }
        controller?.deleteEventsFromLastHour()
    }

    @objc private func resetLocalMemory() {
        guard confirmDestructiveAction(message: "Delete all Observer events from local memory?") else {
            return
        }
        controller?.resetLocalMemory()
    }

    @objc private func showWidget() {
        widgetController?.show()
    }

    @objc private func hideWidget() {
        widgetController?.hide()
    }

    @objc private func resetWidgetPosition() {
        widgetController?.resetPosition()
        widgetController?.show()
    }

    @objc private func requestAccessibilityAccess() {
        controller?.requestAccessibilityAccess()
    }

    @objc private func requestCameraAccess() {
        controller?.requestCameraAccess()
    }

    @objc private func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func requestScreenRecordingAccess() {
        controller?.requestScreenRecordingAccess()
    }

    @objc private func printCurrentSetup() {
        guard let description = controller?.currentSetupDescription else {
            return
        }
        print(description)
    }

    @objc private func openDataFolder() {
        guard let folder = controller?.dataFolder else {
            return
        }
        NSWorkspace.shared.open(folder)
    }

    @objc private func openSettingsFile() {
        openDataFile("observer-settings.json")
    }

    @objc private func openPrivacyFile() {
        openDataFile("privacy.json")
    }

    @objc private func openExportsFolder() {
        guard let folder = controller?.dataFolder.appendingPathComponent("Exports", isDirectory: true) else {
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func quit() {
        dashboardServer?.stop()
        controller?.recordShutdown()
        NSApp.terminate(nil)
    }

    private func presentStartupFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Observer could not start"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func confirmDestructiveAction(message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "This only affects Observer's local event database."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func openDataFile(_ filename: String) {
        guard let file = controller?.dataFolder.appendingPathComponent(filename) else {
            return
        }
        NSWorkspace.shared.open(file)
    }

    private func runDeveloperAutomationIfRequested() {
        let environment = ProcessInfo.processInfo.environment

        if environment["OBSERVER_AUTOSTART"] == "1" {
            startObserving()
        }

        if let collectAfterValue = environment["OBSERVER_COLLECT_CONTEXT_AFTER_SECONDS"],
           let collectAfter = TimeInterval(collectAfterValue) {
            Timer.scheduledTimer(withTimeInterval: collectAfter, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    _ = self?.controller?.generateLocalSummary()
                    _ = self?.controller?.collectContextPack()
                }
            }
        }

        if let causalAfterValue = environment["OBSERVER_EXPORT_CAUSAL_AFTER_SECONDS"],
           let causalAfter = TimeInterval(causalAfterValue) {
            Timer.scheduledTimer(withTimeInterval: causalAfter, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    _ = self?.controller?.exportCausalUnderstandingReport()
                }
            }
        }

        if let dailyAfterValue = environment["OBSERVER_EXPORT_DAILY_ACTIVITY_AFTER_SECONDS"],
           let dailyAfter = TimeInterval(dailyAfterValue) {
            Timer.scheduledTimer(withTimeInterval: dailyAfter, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    _ = self?.controller?.exportDailyActivityReport()
                }
            }
        }

        guard
            let quitAfterValue = environment["OBSERVER_QUIT_AFTER_SECONDS"],
            let quitAfter = TimeInterval(quitAfterValue)
        else {
            return
        }

        Timer.scheduledTimer(withTimeInterval: quitAfter, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.quit()
            }
        }
    }

    private func startScheduleReconciliation() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.controller?.reconcileScheduleGate()
            }
        }
    }

    private func startConfiguredServices() {
        guard let controller else {
            return
        }

        if controller.settings.startObservingOnLaunch {
            startObserving()
        }

        if controller.settings.startCameraAttentionOnLaunch {
            startCameraAttention()
        }

        startScheduleReconciliation()
    }

    private func startPermissionReconciliation() {
        cameraPermissionTimer?.invalidate()
        cameraPermissionTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.controller?.reconcileCameraPermissionAndStartIfNeeded()
            }
        }
    }
}
