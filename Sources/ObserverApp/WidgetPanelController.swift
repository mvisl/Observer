import AppKit
import Foundation

@MainActor
final class WidgetPanelController {
    private let panel: FloatingWidgetPanel
    private let widgetView: ObserverWidgetView

    init(onInsightRequest: @escaping (TimeInterval) -> String?) {
        let size = Self.storedWidgetSize() ?? Self.defaultWidgetSize
        widgetView = ObserverWidgetView(
            frame: NSRect(origin: .zero, size: size),
            onInsightRequest: onInsightRequest
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

    fileprivate static func applyWidgetSize(_ size: CGSize, to window: NSWindow, persist: Bool = true) {
        let clampedSize = clampedSize(size)
        let clampedOrigin = clampedOrigin(window.frame.origin, size: clampedSize)
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
    private let appLabel = NSTextField(labelWithString: "")
    private let contextLabel = NSTextField(labelWithString: "No active context yet")
    private let insightLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "Camera: display 1, right")
    private let hintLabel = NSTextField(labelWithString: "")
    private let onInsightRequest: (TimeInterval) -> String?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var dragStartWindowSize: CGSize?
    private var dragMode: DragMode?
    private var state: ObserverViewState?
    private var refreshTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var previousSizeBeforeInsight: CGSize?
    private var isInsightExpanded = false

    private enum DragMode {
        case move
        case resize
    }

    init(frame frameRect: NSRect, onInsightRequest: @escaping (TimeInterval) -> String?) {
        self.onInsightRequest = onInsightRequest
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
        if !isInsightExpanded {
            insightLabel.isHidden = true
        }
        statusDot.layer?.backgroundColor = dotColor(for: state.mode).cgColor
        refreshSessionDuration()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if moreButton.frame.insetBy(dx: -8, dy: -8).contains(point) {
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
        [statusDot, statusLabel, moreButton, appLabel, contextLabel, insightLabel, metaLabel, hintLabel].forEach {
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
        moreButton.action = #selector(showInsightMenu)

        appLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        appLabel.textColor = .labelColor
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.maximumNumberOfLines = 1

        contextLabel.font = .systemFont(ofSize: 12, weight: .medium)
        contextLabel.textColor = .labelColor
        contextLabel.lineBreakMode = .byTruncatingTail
        contextLabel.maximumNumberOfLines = 1

        insightLabel.font = .systemFont(ofSize: 11, weight: .medium)
        insightLabel.textColor = .secondaryLabelColor
        insightLabel.lineBreakMode = .byTruncatingTail
        insightLabel.maximumNumberOfLines = 5
        insightLabel.isHidden = true

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

            appLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            appLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            appLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),

            contextLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            contextLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            contextLabel.topAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 4),

            insightLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            insightLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            insightLabel.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 8),

            metaLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            metaLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            metaLabel.topAnchor.constraint(equalTo: insightLabel.bottomAnchor, constant: 5),

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

    @objc private func showInsightMenu() {
        let menu = NSMenu()
        [
            ("Insight: 30 min", 30),
            ("Insight: 1 hour", 60),
            ("Insight: 2 hours", 120),
            ("Insight: today", 0)
        ].forEach { title, minutes in
            let item = menuItem(title, action: #selector(selectInsightInterval(_:)))
            item.representedObject = minutes
            menu.addItem(item)
        }
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: moreButton)
        }
    }

    @objc private func selectInsightInterval(_ sender: NSMenuItem) {
        let minutes = sender.representedObject as? Int ?? 30
        let interval = minutes == 0 ? 0 : TimeInterval(minutes * 60)
        let title = minutes == 0 ? "Сегодня" : "\(minutes) мин"
        let text = onInsightRequest(interval) ?? "Инсайт недоступен."
        expandInsight(title: title, text: text)
    }

    private func expandInsight(title: String, text: String) {
        guard let window else {
            return
        }
        if !isInsightExpanded {
            previousSizeBeforeInsight = window.frame.size
        }
        isInsightExpanded = true
        insightLabel.stringValue = "\(title)\n\(text)"
        insightLabel.isHidden = false
        WidgetPanelController.applyWidgetSize(
            CGSize(width: window.frame.width, height: 168),
            to: window,
            persist: false
        )
    }

    private func collapseInsight() {
        guard isInsightExpanded, let window else {
            return
        }
        isInsightExpanded = false
        insightLabel.isHidden = true
        let target = previousSizeBeforeInsight ?? WidgetPanelController.defaultWidgetSize
        previousSizeBeforeInsight = nil
        WidgetPanelController.applyWidgetSize(target, to: window, persist: false)
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
