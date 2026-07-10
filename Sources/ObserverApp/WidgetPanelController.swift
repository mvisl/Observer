import AppKit
import Foundation

@MainActor
final class WidgetPanelController {
    private let panel: FloatingWidgetPanel
    private let widgetView: ObserverWidgetView

    init(
        onInsightRequest: @escaping (TimeInterval) -> String?,
        onInsightOpened: @escaping () -> Void,
        onSecurityArtifactRequest: @escaping () -> URL?,
        onCalibrationSample: @escaping (Int, Int, Int?, Int?) -> Void,
        onCalibrationAction: @escaping (String) -> Void
    ) {
        let size = Self.storedWidgetSize() ?? Self.defaultWidgetSize
        widgetView = ObserverWidgetView(
            frame: NSRect(origin: .zero, size: size),
            onInsightRequest: onInsightRequest,
            onInsightOpened: onInsightOpened,
            onSecurityArtifactRequest: onSecurityArtifactRequest,
            onCalibrationSample: onCalibrationSample,
            onCalibrationAction: onCalibrationAction
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
        normalizePanelSizeIfNeeded()
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
        normalizePanelSizeIfNeeded()
        widgetView.update(state)
    }

    private func normalizePanelSizeIfNeeded() {
        let clamped = Self.clampedSize(panel.frame.size)
        guard abs(panel.frame.width - clamped.width) > 0.5 || abs(panel.frame.height - clamped.height) > 0.5 else {
            return
        }
        Self.applyWidgetSize(clamped, to: panel, anchor: .topRight)
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
        guard let frame = screenFrame(for: origin, size: size) else {
            return origin
        }

        return CGPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - size.width),
            y: min(max(origin.y, frame.minY), frame.maxY - size.height)
        )
    }

    private static func screenFrame(for origin: CGPoint, size: CGSize) -> CGRect? {
        let candidate = CGRect(origin: origin, size: size)
        let center = CGPoint(x: candidate.midX, y: candidate.midY)
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(center) }) {
            return screen.visibleFrame
        }
        return NSScreen.screens
            .map(\.visibleFrame)
            .max { lhs, rhs in
                lhs.intersection(candidate).width * lhs.intersection(candidate).height
                    < rhs.intersection(candidate).width * rhs.intersection(candidate).height
            }
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
            width: min(max(size.width, 190), 340),
            height: min(max(size.height, 68), 240)
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
    private let calibrationButton = NSButton(title: "Калибровка", target: nil, action: nil)
    private let calibrationContainer = NSView()
    private let finishCalibrationButton = NSButton(title: "Закончить", target: nil, action: nil)
    private let resetCalibrationButton = NSButton(title: "Сбросить", target: nil, action: nil)
    private let confirmCalibrationButton = NSButton(title: "Подтвердить", target: nil, action: nil)
    private let metaLabel = NSTextField(labelWithString: "Camera: display 1, right")
    private let hintLabel = NSTextField(labelWithString: "")
    private let onInsightRequest: (TimeInterval) -> String?
    private let onInsightOpened: () -> Void
    private let onSecurityArtifactRequest: () -> URL?
    private let onCalibrationSample: (Int, Int, Int?, Int?) -> Void
    private let onCalibrationAction: (String) -> Void
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var dragStartWindowSize: CGSize?
    private var dragMode: DragMode?
    private var state: ObserverViewState?
    private var refreshTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var previousSizeBeforeInsight: CGSize?
    private var isInsightExpanded = false
    private var isCalibrationMode = false
    private var calibrationViews: [NSView] = []
    private var calibrationStartedAppName: String?
    private var lastCalibrationSelection: CalibrationSelection?
    private var selectedInsightMinutes = UserDefaults.standard.object(forKey: "widget.insight.minutes") as? Int ?? 30

    private enum DragMode {
        case move
        case resize
    }

    private struct CalibrationSelection {
        let displayIndex: Int
        let cellIndex: Int
        let predictedDisplayIndex: Int?
        let predictedCellIndex: Int?

        var isCorrect: Bool {
            predictedDisplayIndex == displayIndex && predictedCellIndex == cellIndex
        }
    }

    init(
        frame frameRect: NSRect,
        onInsightRequest: @escaping (TimeInterval) -> String?,
        onInsightOpened: @escaping () -> Void,
        onSecurityArtifactRequest: @escaping () -> URL?,
        onCalibrationSample: @escaping (Int, Int, Int?, Int?) -> Void,
        onCalibrationAction: @escaping (String) -> Void
    ) {
        self.onInsightRequest = onInsightRequest
        self.onInsightOpened = onInsightOpened
        self.onSecurityArtifactRequest = onSecurityArtifactRequest
        self.onCalibrationSample = onCalibrationSample
        self.onCalibrationAction = onCalibrationAction
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
        if isCalibrationMode {
            if calibrationStartedAppName != nil, calibrationStartedAppName != state.appName {
                onCalibrationAction("stopped_app_switch")
                leaveCalibrationMode()
                return
            }
            contextLabel.stringValue = state.calibration.predictionText
            rebuildCalibrationGrid(state.calibration)
        } else if !isInsightExpanded {
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
            calibrationButton,
            calibrationContainer,
            finishCalibrationButton,
            resetCalibrationButton,
            confirmCalibrationButton,
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

        calibrationButton.bezelStyle = .rounded
        calibrationButton.controlSize = .small
        calibrationButton.font = .systemFont(ofSize: 11, weight: .medium)
        calibrationButton.target = self
        calibrationButton.action = #selector(startCalibrationMode)
        calibrationButton.isHidden = true

        calibrationContainer.wantsLayer = true
        calibrationContainer.isHidden = true

        [finishCalibrationButton, resetCalibrationButton, confirmCalibrationButton].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .small
            $0.font = .systemFont(ofSize: 11, weight: .medium)
            $0.isHidden = true
        }
        finishCalibrationButton.target = self
        finishCalibrationButton.action = #selector(finishCalibrationWithoutSaving)
        resetCalibrationButton.target = self
        resetCalibrationButton.action = #selector(resetCalibrationSession)
        confirmCalibrationButton.target = self
        confirmCalibrationButton.action = #selector(confirmCalibrationSession)

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

            calibrationButton.leadingAnchor.constraint(equalTo: securityFolderButton.trailingAnchor, constant: 8),
            calibrationButton.centerYAnchor.constraint(equalTo: securityFolderButton.centerYAnchor),
            calibrationButton.widthAnchor.constraint(equalToConstant: 92),
            calibrationButton.heightAnchor.constraint(equalToConstant: 22),

            calibrationContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            calibrationContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            calibrationContainer.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 10),
            calibrationContainer.heightAnchor.constraint(equalToConstant: 94),

            finishCalibrationButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            finishCalibrationButton.topAnchor.constraint(equalTo: calibrationContainer.bottomAnchor, constant: 8),
            finishCalibrationButton.widthAnchor.constraint(equalToConstant: 82),
            finishCalibrationButton.heightAnchor.constraint(equalToConstant: 22),

            resetCalibrationButton.leadingAnchor.constraint(equalTo: finishCalibrationButton.trailingAnchor, constant: 8),
            resetCalibrationButton.centerYAnchor.constraint(equalTo: finishCalibrationButton.centerYAnchor),
            resetCalibrationButton.widthAnchor.constraint(equalToConstant: 74),
            resetCalibrationButton.heightAnchor.constraint(equalToConstant: 22),

            confirmCalibrationButton.leadingAnchor.constraint(equalTo: resetCalibrationButton.trailingAnchor, constant: 8),
            confirmCalibrationButton.centerYAnchor.constraint(equalTo: finishCalibrationButton.centerYAnchor),
            confirmCalibrationButton.widthAnchor.constraint(equalToConstant: 98),
            confirmCalibrationButton.heightAnchor.constraint(equalToConstant: 22),

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
        isCalibrationMode = false
        intervalControl.isHidden = false
        descriptionLabel.isHidden = false
        recommendationLabel.isHidden = false
        calibrationButton.isHidden = false
        hideCalibrationControls()
        updateInsightContent()
        layoutSubtreeIfNeeded()
        onInsightOpened()
        let expandedHeight = insightExpandedHeight()
        WidgetPanelController.applyWidgetSize(
            CGSize(width: window.frame.width, height: expandedHeight),
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
        isCalibrationMode = false
        hideInsightControls()
        hideCalibrationControls()
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
        calibrationButton.isHidden = false
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
        calibrationButton.isHidden = true
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
            .union(calibrationButton.frame)
            .union(calibrationContainer.frame)
            .union(finishCalibrationButton.frame)
            .union(resetCalibrationButton.frame)
            .union(confirmCalibrationButton.frame)
            .insetBy(dx: -8, dy: -8)
    }

    private func insightExpandedHeight() -> CGFloat {
        if isCalibrationMode {
            return 216
        }
        if !securityFolderButton.isHidden || !calibrationButton.isHidden {
            return 204
        }
        return 174
    }

    @objc private func startCalibrationMode() {
        guard let window else {
            return
        }
        isCalibrationMode = true
        calibrationStartedAppName = state?.appName
        lastCalibrationSelection = nil
        intervalControl.isHidden = true
        descriptionLabel.isHidden = true
        recommendationLabel.isHidden = true
        securityFolderButton.isHidden = true
        calibrationButton.isHidden = true
        calibrationContainer.isHidden = false
        finishCalibrationButton.isHidden = false
        resetCalibrationButton.isHidden = false
        confirmCalibrationButton.isHidden = false
        contextLabel.stringValue = state?.calibration.predictionText ?? "Калибровка: камера ждёт взгляд"
        if let state {
            rebuildCalibrationGrid(state.calibration)
        }
        layoutSubtreeIfNeeded()
        onCalibrationAction("started")
        WidgetPanelController.applyWidgetSize(
            CGSize(width: window.frame.width, height: insightExpandedHeight()),
            to: window,
            persist: false,
            anchor: .topRight
        )
    }

    @objc private func finishCalibrationWithoutSaving() {
        onCalibrationAction("finished_without_commit")
        leaveCalibrationMode()
    }

    @objc private func resetCalibrationSession() {
        onCalibrationAction("reset")
        leaveCalibrationMode()
    }

    @objc private func confirmCalibrationSession() {
        onCalibrationAction("confirmed")
        leaveCalibrationMode()
    }

    private func leaveCalibrationMode() {
        isCalibrationMode = false
        calibrationStartedAppName = nil
        lastCalibrationSelection = nil
        hideCalibrationControls()
        if isInsightExpanded {
            intervalControl.isHidden = false
            descriptionLabel.isHidden = false
            recommendationLabel.isHidden = false
            updateInsightContent()
            layoutSubtreeIfNeeded()
            if let window {
                WidgetPanelController.applyWidgetSize(
                    CGSize(width: window.frame.width, height: insightExpandedHeight()),
                    to: window,
                    persist: false,
                    anchor: .topRight
                )
            }
        }
    }

    private func hideCalibrationControls() {
        calibrationContainer.isHidden = true
        finishCalibrationButton.isHidden = true
        resetCalibrationButton.isHidden = true
        confirmCalibrationButton.isHidden = true
        calibrationViews.forEach { $0.removeFromSuperview() }
        calibrationViews = []
    }

    private func rebuildCalibrationGrid(_ calibration: WidgetCalibrationState?) {
        calibrationViews.forEach { $0.removeFromSuperview() }
        calibrationViews = []
        guard isCalibrationMode, let calibration else {
            return
        }

        let displays = calibration.displays.isEmpty
            ? [WidgetCalibrationDisplay(index: 0, title: "Экран", columns: 3, rows: 3, predictedCell: nil)]
            : calibration.displays
        let spacing: CGFloat = 10
        let availableWidth = max(120, calibrationContainer.bounds.width > 20 ? calibrationContainer.bounds.width : bounds.width - 28)
        let displayWidth = (availableWidth - spacing * CGFloat(max(0, displays.count - 1))) / CGFloat(displays.count)
        let displayHeight = max(72, calibrationContainer.bounds.height > 20 ? calibrationContainer.bounds.height : 94)

        for (offset, display) in displays.enumerated() {
            let columnOriginX = CGFloat(offset) * (displayWidth + spacing)
            let titleHeight: CGFloat = 16
            let title = NSTextField(labelWithString: display.title)
            title.font = .systemFont(ofSize: 10, weight: .semibold)
            title.textColor = .secondaryLabelColor
            title.alignment = .center
            title.frame = CGRect(x: columnOriginX, y: displayHeight - titleHeight, width: displayWidth, height: titleHeight)
            calibrationContainer.addSubview(title)
            calibrationViews.append(title)

            let gridHeight = displayHeight - titleHeight - 4
            let side = min(displayWidth, gridHeight)
            let gridX = columnOriginX + (displayWidth - side) / 2
            let gridY = max(0, (gridHeight - side) / 2)
            let cellWidth = side / CGFloat(display.columns)
            let cellHeight = side / CGFloat(display.rows)
            for row in 0..<display.rows {
                for column in 0..<display.columns {
                    let cellIndex = row * display.columns + column
                    let isPredicted = cellIndex == display.predictedCell
                    let isSelected = lastCalibrationSelection?.displayIndex == display.index
                        && lastCalibrationSelection?.cellIndex == cellIndex
                    let button = NSButton(title: "", target: self, action: #selector(selectCalibrationCell(_:)))
                    button.tag = display.index * 100 + cellIndex
                    button.bezelStyle = .regularSquare
                    button.isBordered = false
                    button.wantsLayer = true
                    button.layer?.cornerRadius = 3
                    button.layer?.borderWidth = 1
                    button.layer?.borderColor = borderColor(isPredicted: isPredicted, isSelected: isSelected).cgColor
                    button.layer?.backgroundColor = calibrationCellColor(isPredicted: isPredicted, isSelected: isSelected).cgColor
                    button.frame = CGRect(
                        x: gridX + CGFloat(column) * cellWidth + 1,
                        y: gridY + CGFloat(display.rows - row - 1) * cellHeight + 1,
                        width: max(12, cellWidth - 2),
                        height: max(12, cellHeight - 2)
                    )
                    calibrationContainer.addSubview(button)
                    calibrationViews.append(button)
                }
            }
        }
    }

    private func calibrationCellColor(isPredicted: Bool, isSelected: Bool) -> NSColor {
        guard let selection = lastCalibrationSelection, isSelected else {
            return isPredicted
                ? NSColor.white.withAlphaComponent(0.72)
                : NSColor.controlBackgroundColor.withAlphaComponent(0.22)
        }
        return selection.isCorrect
            ? NSColor.systemGreen.withAlphaComponent(0.58)
            : NSColor.systemRed.withAlphaComponent(0.58)
    }

    private func borderColor(isPredicted: Bool, isSelected: Bool) -> NSColor {
        if isSelected {
            return .white.withAlphaComponent(0.9)
        }
        if isPredicted {
            return .white.withAlphaComponent(1)
        }
        return .separatorColor.withAlphaComponent(0.65)
    }

    @objc private func selectCalibrationCell(_ sender: NSButton) {
        let displayIndex = sender.tag / 100
        let cellIndex = sender.tag % 100
        let prediction = state?.calibration
        lastCalibrationSelection = CalibrationSelection(
            displayIndex: displayIndex,
            cellIndex: cellIndex,
            predictedDisplayIndex: prediction?.predictedDisplayIndex,
            predictedCellIndex: prediction?.predictedCellIndex
        )
        onCalibrationSample(
            displayIndex,
            cellIndex,
            prediction?.predictedDisplayIndex,
            prediction?.predictedCellIndex
        )
        rebuildCalibrationGrid(state?.calibration)
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
