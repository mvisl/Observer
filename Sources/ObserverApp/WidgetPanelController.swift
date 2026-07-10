import AppKit
import Foundation

@MainActor
final class WidgetPanelController {
    private let panel: FloatingWidgetPanel
    private let widgetView: ObserverWidgetView

    init(
        onInsightRequest: @escaping (TimeInterval) -> String?,
        onInsightOpened: @escaping () -> Void,
        onSecurityArtifactRequest: @escaping () -> URL?
    ) {
        let size = Self.storedWidgetSize() ?? Self.defaultWidgetSize
        widgetView = ObserverWidgetView(
            frame: NSRect(origin: .zero, size: size),
            onInsightRequest: onInsightRequest,
            onInsightOpened: onInsightOpened,
            onSecurityArtifactRequest: onSecurityArtifactRequest
        )
        panel = FloatingWidgetPanel(
            contentRect: widgetView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = widgetView
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        positionPanel()
    }

    func show() {
        positionPanelIfNeeded()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: "widget.origin.x")
        UserDefaults.standard.removeObject(forKey: "widget.origin.y")
        UserDefaults.standard.removeObject(forKey: "widget.width")
        UserDefaults.standard.removeObject(forKey: "widget.height")
        panel.setFrame(NSRect(origin: panel.frame.origin, size: Self.defaultWidgetSize), display: true)
        positionPanel()
    }

    func update(_ state: ObserverViewState) {
        widgetView.update(state)
    }

    private func positionPanelIfNeeded() {
        if panel.frame.origin == .zero {
            positionPanel()
        }
    }

    private func positionPanel() {
        if let storedOrigin = storedWidgetOrigin() {
            panel.setFrameOrigin(clampedOrigin(storedOrigin, size: panel.frame.size))
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else {
            return
        }

        let margin: CGFloat = 18
        let size = panel.frame.size
        let origin = CGPoint(
            x: visibleFrame.maxX - size.width - margin,
            y: visibleFrame.maxY - size.height - margin
        )
        panel.setFrameOrigin(origin)
    }

    private func storedWidgetOrigin() -> CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "widget.origin.x") != nil,
              defaults.object(forKey: "widget.origin.y") != nil
        else {
            return nil
        }

        return CGPoint(
            x: defaults.double(forKey: "widget.origin.x"),
            y: defaults.double(forKey: "widget.origin.y")
        )
    }

    fileprivate static func saveWidgetOrigin(_ origin: CGPoint) {
        let defaults = UserDefaults.standard
        defaults.set(origin.x, forKey: "widget.origin.x")
        defaults.set(origin.y, forKey: "widget.origin.y")
    }

    fileprivate static func saveWidgetSize(_ size: CGSize) {
        let clamped = clampedSize(size)
        let defaults = UserDefaults.standard
        defaults.set(clamped.width, forKey: "widget.width")
        defaults.set(clamped.height, forKey: "widget.height")
    }

    fileprivate enum ResizeAnchor {
        case origin
        case topRight
    }

    fileprivate static func applyWidgetSize(
        _ size: CGSize,
        to window: NSWindow,
        persist: Bool = true,
        anchor: ResizeAnchor = .origin
    ) {
        let clampedSize = clampedSize(size)
        let proposedOrigin: CGPoint
        switch anchor {
        case .origin:
            proposedOrigin = window.frame.origin
        case .topRight:
            proposedOrigin = CGPoint(
                x: window.frame.maxX - clampedSize.width,
                y: window.frame.maxY - clampedSize.height
            )
        }
        let clampedOrigin = clampedOrigin(proposedOrigin, size: clampedSize)
        window.setFrame(NSRect(origin: clampedOrigin, size: clampedSize), display: true)
        if persist {
            saveWidgetOrigin(clampedOrigin)
            saveWidgetSize(clampedSize)
        }
    }

    fileprivate static func clampedOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let unionFrame = visibleFrames.reduce(visibleFrames.first ?? .zero) { $0.union($1) }
        guard !unionFrame.isEmpty else {
            return origin
        }

        return CGPoint(
            x: min(max(origin.x, unionFrame.minX), unionFrame.maxX - size.width),
            y: min(max(origin.y, unionFrame.minY), unionFrame.maxY - size.height)
        )
    }

    private func clampedOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        Self.clampedOrigin(origin, size: size)
    }

    fileprivate static let defaultWidgetSize = CGSize(width: 248, height: 76)
    fileprivate static let compactWidgetSize = CGSize(width: 220, height: 70)
    fileprivate static let comfortableWidgetSize = CGSize(width: 280, height: 76)
    fileprivate static let wideWidgetSize = CGSize(width: 340, height: 76)

    private static func storedWidgetSize() -> CGSize? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "widget.width") != nil,
              defaults.object(forKey: "widget.height") != nil
        else {
            return nil
        }

        return clampedSize(
            CGSize(
                width: defaults.double(forKey: "widget.width"),
                height: defaults.double(forKey: "widget.height")
            )
        )
    }

    private static func clampedSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, 190), 360),
            height: min(max(size.height, 68), 190)
        )
    }
}

final class FloatingWidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ObserverWidgetView: NSView {
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "Paused")
    private let moreButton = NSButton(title: "...", target: nil, action: nil)
    private let securityBadgeLabel = NSTextField(labelWithString: "")
    private let appLabel = NSTextField(labelWithString: "")
    private let contextLabel = NSTextField(labelWithString: "No active context yet")
    private let intervalControl = NSSegmentedControl(
        labels: ["30м", "1ч", "2ч", "день"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let descriptionLabel = NSTextField(labelWithString: "")
    private let recommendationLabel = NSTextField(labelWithString: "")
    private let securityFolderButton = NSButton(title: "Папка", target: nil, action: nil)
    private let metaLabel = NSTextField(labelWithString: "Camera: display 1, right")
    private let hintLabel = NSTextField(labelWithString: "")
    private let onInsightRequest: (TimeInterval) -> String?
    private let onInsightOpened: () -> Void
    private let onSecurityArtifactRequest: () -> URL?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var dragStartWindowSize: CGSize?
    private var dragMode: DragMode?
    private var state: ObserverViewState?
    private var refreshTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var previousSizeBeforeInsight: CGSize?
    private var isInsightExpanded = false
    private var selectedInsightMinutes = UserDefaults.standard.object(forKey: "widget.insight.minutes") as? Int ?? 30

    private enum DragMode {
        case move
        case resize
    }

    init(
        frame frameRect: NSRect,
        onInsightRequest: @escaping (TimeInterval) -> String?,
        onInsightOpened: @escaping () -> Void,
        onSecurityArtifactRequest: @escaping () -> URL?
    ) {
        self.onInsightRequest = onInsightRequest
        self.onInsightOpened = onInsightOpened
        self.onSecurityArtifactRequest = onSecurityArtifactRequest
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        layer?.borderWidth = 1

        configureSubviews()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSessionDuration()
            }
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    func update(_ state: ObserverViewState) {
        self.state = state
        statusLabel.stringValue = state.mode.displayText
        appLabel.stringValue = appLine(for: state)
        contextLabel.stringValue = summaryLine(for: state)
        metaLabel.stringValue = ""
        hintLabel.stringValue = ""
        metaLabel.isHidden = true
        hintLabel.isHidden = true
        updateSecurityBadge(count: state.securityIncidentCount)
        if !isInsightExpanded {
            hideInsightControls()
        }
        statusDot.layer?.backgroundColor = dotColor(for: state.mode).cgColor
        refreshSessionDuration()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if moreButton.frame.insetBy(dx: -8, dy: -8).contains(point) {
            return
        }
        if isInsightExpanded, expandedControlsFrame.contains(point) {
            return
        }
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        dragStartWindowSize = window?.frame.size
        dragMode = isResizeHotspot(event) ? .resize : .move
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let dragStartMouseLocation,
            let dragStartWindowOrigin
        else {
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        let delta = CGPoint(
            x: currentMouseLocation.x - dragStartMouseLocation.x,
            y: currentMouseLocation.y - dragStartMouseLocation.y
        )

        if dragMode == .resize {
            guard let dragStartWindowSize else {
                return
            }

            let newSize = CGSize(
                width: dragStartWindowSize.width + delta.x,
                height: dragStartWindowSize.height
            )
            WidgetPanelController.applyWidgetSize(newSize, to: window)
            return
        }

        let newOrigin = CGPoint(
            x: dragStartWindowOrigin.x + delta.x,
            y: dragStartWindowOrigin.y + delta.y
        )
        window.setFrameOrigin(WidgetPanelController.clampedOrigin(newOrigin, size: window.frame.size))
    }

    override func mouseUp(with event: NSEvent) {
        if let origin = window?.frame.origin {
            WidgetPanelController.saveWidgetOrigin(origin)
        }
        if let size = window?.frame.size {
            WidgetPanelController.saveWidgetSize(size)
        }
        dragMode = nil
        dragStartWindowSize = nil
    }

    override func mouseExited(with event: NSEvent) {
        collapseInsight()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(menuItem("Small", action: #selector(setCompactSize)))
        menu.addItem(menuItem("Medium", action: #selector(setComfortableSize)))
        menu.addItem(menuItem("Wide", action: #selector(setWideSize)))
        return menu
    }

    private func configureSubviews() {
        [
            statusDot,
            statusLabel,
            moreButton,
            securityBadgeLabel,
            appLabel,
            contextLabel,
            intervalControl,
            descriptionLabel,
            recommendationLabel,
            securityFolderButton,
            metaLabel,
            hintLabel
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.backgroundColor = NSColor.systemYellow.cgColor

        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .labelColor

        moreButton.bezelStyle = .regularSquare
        moreButton.isBordered = false
        moreButton.font = .systemFont(ofSize: 14, weight: .bold)
        moreButton.contentTintColor = .secondaryLabelColor
        moreButton.target = self
        moreButton.action = #selector(toggleInsightPanel)

        securityBadgeLabel.font = .systemFont(ofSize: 9, weight: .bold)
        securityBadgeLabel.textColor = .white
        securityBadgeLabel.alignment = .center
        securityBadgeLabel.wantsLayer = true
        securityBadgeLabel.layer?.backgroundColor = NSColor.systemRed.cgColor
        securityBadgeLabel.layer?.cornerRadius = 7
        securityBadgeLabel.isHidden = true

        appLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        appLabel.textColor = .labelColor
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.maximumNumberOfLines = 1

        contextLabel.font = .systemFont(ofSize: 12, weight: .medium)
        contextLabel.textColor = .labelColor
        contextLabel.lineBreakMode = .byTruncatingTail
        contextLabel.maximumNumberOfLines = 1

        intervalControl.segmentStyle = .automatic
        intervalControl.controlSize = .small
        intervalControl.font = .systemFont(ofSize: 11, weight: .medium)
        intervalControl.target = self
        intervalControl.action = #selector(selectInsightInterval(_:))
        intervalControl.sendAction(on: [.leftMouseUp])
        intervalControl.isHidden = true
        intervalControl.setWidth(48, forSegment: 0)
        intervalControl.setWidth(44, forSegment: 1)
        intervalControl.setWidth(44, forSegment: 2)
        intervalControl.setWidth(56, forSegment: 3)
        updateIntervalControlState()

        descriptionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        descriptionLabel.textColor = .labelColor
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.maximumNumberOfLines = 2
        descriptionLabel.isHidden = true

        recommendationLabel.font = .systemFont(ofSize: 11, weight: .medium)
        recommendationLabel.textColor = .secondaryLabelColor
        recommendationLabel.lineBreakMode = .byTruncatingTail
        recommendationLabel.maximumNumberOfLines = 2
        recommendationLabel.isHidden = true

        securityFolderButton.bezelStyle = .rounded
        securityFolderButton.controlSize = .small
        securityFolderButton.font = .systemFont(ofSize: 11, weight: .medium)
        securityFolderButton.target = self
        securityFolderButton.action = #selector(openSecurityFolder)
        securityFolderButton.isHidden = true

        metaLabel.font = .systemFont(ofSize: 11, weight: .medium)
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.maximumNumberOfLines = 1
        metaLabel.isHidden = true

        hintLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.maximumNumberOfLines = 1
        hintLabel.isHidden = true

        NSLayoutConstraint.activate([
            statusDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            statusDot.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),

            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: statusDot.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -8),

            moreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            moreButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 28),
            moreButton.heightAnchor.constraint(equalToConstant: 24),

            securityBadgeLabel.centerXAnchor.constraint(equalTo: moreButton.trailingAnchor, constant: -5),
            securityBadgeLabel.centerYAnchor.constraint(equalTo: moreButton.topAnchor, constant: 5),
            securityBadgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
            securityBadgeLabel.heightAnchor.constraint(equalToConstant: 14),

            appLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            appLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            appLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),

            contextLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            contextLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            contextLabel.topAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 4),

            intervalControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            intervalControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            intervalControl.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 8),
            intervalControl.heightAnchor.constraint(equalToConstant: 22),

            descriptionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            descriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            descriptionLabel.topAnchor.constraint(equalTo: intervalControl.bottomAnchor, constant: 8),

            recommendationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            recommendationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            recommendationLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 5),

            securityFolderButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            securityFolderButton.topAnchor.constraint(equalTo: recommendationLabel.bottomAnchor, constant: 6),
            securityFolderButton.widthAnchor.constraint(equalToConstant: 58),
            securityFolderButton.heightAnchor.constraint(equalToConstant: 22),

            metaLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            metaLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            metaLabel.topAnchor.constraint(equalTo: securityFolderButton.bottomAnchor, constant: 5),

            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            hintLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 3)
        ])
    }

    private func isResizeHotspot(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        return point.x >= bounds.maxX - 22
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleInsightPanel() {
        if isInsightExpanded {
            collapseInsight()
        } else {
            expandInsight()
        }
    }

    @objc private func selectInsightInterval(_ sender: NSSegmentedControl) {
        let minutes = minutesForSegment(sender.selectedSegment)
        selectedInsightMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: "widget.insight.minutes")
        updateInsightContent()
    }

    private func expandInsight() {
        guard let window else {
            return
        }
        if !isInsightExpanded {
            previousSizeBeforeInsight = window.frame.size
        }
        isInsightExpanded = true
        intervalControl.isHidden = false
        descriptionLabel.isHidden = false
        recommendationLabel.isHidden = false
        updateInsightContent()
        onInsightOpened()
        WidgetPanelController.applyWidgetSize(
            CGSize(width: window.frame.width, height: 190),
            to: window,
            persist: false,
            anchor: .topRight
        )
    }

    private func collapseInsight() {
        guard isInsightExpanded, let window else {
            return
        }
        isInsightExpanded = false
        hideInsightControls()
        let target = previousSizeBeforeInsight ?? WidgetPanelController.defaultWidgetSize
        previousSizeBeforeInsight = nil
        WidgetPanelController.applyWidgetSize(target, to: window, persist: false, anchor: .topRight)
    }

    private func updateInsightContent() {
        let interval = selectedInsightMinutes == 0 ? 0 : TimeInterval(selectedInsightMinutes * 60)
        let text = onInsightRequest(interval) ?? "Инсайт недоступен."
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let description = Array(lines.prefix(2)).joined(separator: "\n")
        descriptionLabel.stringValue = description.isEmpty ? "Пока мало наблюдений за выбранный интервал." : description
        recommendationLabel.stringValue = recommendation(for: lines)
        securityFolderButton.isHidden = onSecurityArtifactRequest() == nil
        updateIntervalControlState()
    }

    private func recommendation(for lines: [String]) -> String {
        let joined = lines.joined(separator: " ").lowercased()
        if joined.contains("пауза") || joined.contains("energy") || joined.contains("энерг") {
            return "Рекомендация: коротко закрыть текущий шаг.\nЕсли энергия просела, лучше маленькое действие, не новый контекст."
        }
        if joined.contains("фрикц") || joined.contains("переключ") {
            return "Рекомендация: выбрать один следующий экран.\nСнизить переключения на ближайшие 10 минут."
        }
        if joined.contains("контекст") || joined.contains("фокус") {
            return "Рекомендация: продолжить текущую линию.\nСледующий шаг лучше делать там же, без смены приложения."
        }
        return "Рекомендация: держать текущий контекст.\nЕсли сомневаешься, сформулировать один следующий шаг."
    }

    private func updateIntervalControlState() {
        intervalControl.selectedSegment = segmentForMinutes(selectedInsightMinutes)
    }

    private func hideInsightControls() {
        intervalControl.isHidden = true
        descriptionLabel.isHidden = true
        recommendationLabel.isHidden = true
        securityFolderButton.isHidden = true
    }

    private func updateSecurityBadge(count: Int) {
        securityBadgeLabel.isHidden = count <= 0
        securityBadgeLabel.stringValue = count > 9 ? "9+" : "\(count)"
    }

    private var expandedControlsFrame: CGRect {
        intervalControl.frame
            .union(descriptionLabel.frame)
            .union(recommendationLabel.frame)
            .union(securityFolderButton.frame)
            .insetBy(dx: -8, dy: -8)
    }

    @objc private func openSecurityFolder() {
        guard let url = onSecurityArtifactRequest() else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func segmentForMinutes(_ minutes: Int) -> Int {
        switch minutes {
        case 60:
            return 1
        case 120:
            return 2
        case 0:
            return 3
        default:
            return 0
        }
    }

    private func minutesForSegment(_ segment: Int) -> Int {
        switch segment {
        case 1:
            return 60
        case 2:
            return 120
        case 3:
            return 0
        default:
            return 30
        }
    }

    @objc private func setCompactSize() {
        applyPresetSize(WidgetPanelController.compactWidgetSize)
    }

    @objc private func setComfortableSize() {
        applyPresetSize(WidgetPanelController.comfortableWidgetSize)
    }

    @objc private func setWideSize() {
        applyPresetSize(WidgetPanelController.wideWidgetSize)
    }

    private func applyPresetSize(_ size: CGSize) {
        guard let window else {
            return
        }
        WidgetPanelController.applyWidgetSize(size, to: window)
    }

    private func appLine(for state: ObserverViewState) -> String {
        let appName = state.appName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let appName, !appName.isEmpty {
            return appName
        }

        let context = state.contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.displayAppOnlyFallback
    }

    private func summaryLine(for state: ObserverViewState) -> String {
        let context = state.contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attention = state.attentionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = state.hintText?.trimmingCharacters(in: .whitespacesAndNewlines)

        if context.isHighSignalWidgetContext {
            return context
        }

        if let hint, hint.isWidgetWorthyHint {
            return hint
        }

        if attention.isWidgetWorthyAttention, attention != context {
            return attention
        }

        return context.displayAppOnlyFallback
    }

    private func refreshSessionDuration() {
        guard
            let state,
            state.mode == .observing,
            let sessionStartedAt = state.sessionStartedAt
        else {
            return
        }

        let seconds = Int(Date().timeIntervalSince(sessionStartedAt))
        statusLabel.stringValue = "Watching \(formatDuration(seconds))"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 1 {
            return "0m"
        }
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func dotColor(for mode: ObserverController.Mode) -> NSColor {
        switch mode {
        case .offHours:
            return .systemGray
        case .paused:
            return .systemYellow
        case .observing:
            return .systemGreen
        }
    }
}

private extension String {
    var isHighSignalWidgetContext: Bool {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "Пишет:",
            "Фрикция:",
            "Фокус:",
            "Медиа:",
            "Контент:"
        ].contains { normalized.hasPrefix($0) }
    }

    var isWidgetWorthyHint: Bool {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return false
        }

        let hiddenPrefixes = [
            "Реакция: заметный резкий сдвиг"
        ]
        return !hiddenPrefixes.contains { normalized.hasPrefix($0) }
    }

    var isWidgetWorthyAttention: Bool {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty && normalized != "No active context yet"
    }

    var displayAppOnlyFallback: String {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return "Наблюдаю контекст"
        }

        if let separator = normalized.range(of: " · ") {
            return String(normalized[..<separator.lowerBound])
        }
        if normalized.hasPrefix("Контекст:") {
            return "Наблюдаю контекст"
        }
        return normalized
    }
}
