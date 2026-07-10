import AppKit
import Foundation

@MainActor
final class WidgetPanelController {
    private let panel: FloatingWidgetPanel
    private let widgetView: ObserverWidgetView

    init() {
        widgetView = ObserverWidgetView(frame: NSRect(x: 0, y: 0, width: 330, height: 72))
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
}

final class FloatingWidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ObserverWidgetView: NSView {
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "Paused")
    private let contextLabel = NSTextField(labelWithString: "No active context yet")
    private let metaLabel = NSTextField(labelWithString: "Camera: display 1, right")
    private let hintLabel = NSTextField(labelWithString: "")
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var state: ObserverViewState?
    private var refreshTimer: Timer?

    override init(frame frameRect: NSRect) {
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

    func update(_ state: ObserverViewState) {
        self.state = state
        statusLabel.stringValue = state.mode.displayText
        contextLabel.stringValue = state.contextText
        metaLabel.stringValue = state.attentionText
        hintLabel.stringValue = state.hintText ?? ""
        hintLabel.isHidden = state.hintText == nil
        statusDot.layer?.backgroundColor = dotColor(for: state.mode).cgColor
        refreshSessionDuration()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
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
    }

    private func configureSubviews() {
        [statusDot, statusLabel, contextLabel, metaLabel, hintLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.backgroundColor = NSColor.systemYellow.cgColor

        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .labelColor

        contextLabel.font = .systemFont(ofSize: 12, weight: .medium)
        contextLabel.textColor = .labelColor
        contextLabel.lineBreakMode = .byTruncatingMiddle
        contextLabel.maximumNumberOfLines = 1

        metaLabel.font = .systemFont(ofSize: 10, weight: .regular)
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.maximumNumberOfLines = 1

        hintLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hintLabel.textColor = .controlAccentColor
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
            statusLabel.widthAnchor.constraint(equalToConstant: 70),

            metaLabel.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),
            metaLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            metaLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),

            contextLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            contextLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            contextLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),

            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            hintLabel.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 4)
        ])
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
        case .paused:
            return .systemYellow
        case .observing:
            return .systemGreen
        }
    }
}
