import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class WorkspaceSensor {
    typealias EventHandler = (SensorEvent) -> Void
    typealias ContentPolicy = (String?) -> Bool

    private let topology: WorkspaceTopology
    private let isContentAllowed: ContentPolicy
    private let screenContextRefreshInterval: TimeInterval
    private var timer: Timer?
    private var handler: EventHandler?
    private var lastFocusKey: String?
    private var lastContextKey: String?
    private var lastWritingContextKey: String?
    private var lastWritingContextAt = Date.distantPast
    private var lastContextRefreshAt = Date.distantPast
    private var inputTickCount = 0

    init(
        topology: WorkspaceTopology,
        screenContextRefreshInterval: TimeInterval,
        isContentAllowed: @escaping ContentPolicy
    ) {
        self.topology = topology
        self.screenContextRefreshInterval = screenContextRefreshInterval
        self.isContentAllowed = isContentAllowed
    }

    func start(handler: @escaping EventHandler) {
        self.handler = handler
        emitDisplayInventory()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        handler = nil
        lastFocusKey = nil
        lastContextKey = nil
        lastWritingContextKey = nil
        lastWritingContextAt = .distantPast
        lastContextRefreshAt = .distantPast
        inputTickCount = 0
    }

    func refreshNow() {
        lastFocusKey = nil
        sample()
    }

    private func sample() {
        emitFocusAndContext()
        inputTickCount += 1
        if inputTickCount >= 8 {
            inputTickCount = 0
            emitInputActivity()
        }
    }

    private func emitDisplayInventory() {
        let displays = NSScreen.screens.enumerated().map { index, screen in
            DisplaySnapshot(
                index: index,
                localizedName: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                backingScaleFactor: screen.backingScaleFactor,
                role: topology.displayRole(for: index)
            )
        }
        handler?(.displayInventory(displays))
    }

    private func emitFocusAndContext() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return
        }

        let appID = app.bundleIdentifier
        let pid = app.processIdentifier
        let canReadContent = isContentAllowed(appID)
        let windowTitle = canReadContent ? ActiveWindowReader.focusedWindowTitle(processID: pid) : nil
        let screenIndex = ActiveWindowReader.focusedWindowScreenIndex(processID: pid)
        let displayRole = screenIndex.flatMap { topology.displayRole(for: $0) }

        let focus = AppFocusSnapshot(
            appID: appID,
            appName: app.localizedName ?? "Unknown App",
            processID: pid,
            windowTitle: windowTitle,
            screenIndex: screenIndex,
            displayRole: displayRole,
            contentAllowed: canReadContent
        )

        let key = focus.identityKey
        let focusChanged = key != lastFocusKey
        if focusChanged {
            lastFocusKey = key
            handler?(.appFocus(focus))
        }

        emitScreenContextIfNeeded(
            focus: focus,
            focusChanged: focusChanged,
            processID: pid,
            appID: appID,
            canReadContent: canReadContent,
            screenIndex: screenIndex,
            displayRole: displayRole
        )

        emitWritingContextIfNeeded(
            focus: focus,
            processID: pid,
            appID: appID,
            canReadContent: canReadContent,
            screenIndex: screenIndex,
            displayRole: displayRole
        )
    }

    private func emitScreenContextIfNeeded(
        focus: AppFocusSnapshot,
        focusChanged: Bool,
        processID: pid_t,
        appID: String?,
        canReadContent: Bool,
        screenIndex: Int?,
        displayRole: WorkspaceTopology.DisplayRole?
    ) {
        guard canReadContent else {
            return
        }

        let now = Date()
        guard focusChanged || now.timeIntervalSince(lastContextRefreshAt) >= screenContextRefreshInterval else {
            return
        }

        guard let context = ActiveWindowReader.focusedWindowContext(
            processID: processID,
            appID: appID,
            appName: focus.appName,
            screenIndex: screenIndex,
            displayRole: displayRole
        ) else {
            return
        }

        let contextKey = context.identityKey
        guard focusChanged || contextKey != lastContextKey else {
            lastContextRefreshAt = now
            return
        }

        lastContextKey = contextKey
        lastContextRefreshAt = now
        handler?(.screenContext(context))
    }

    private func emitWritingContextIfNeeded(
        focus: AppFocusSnapshot,
        processID: pid_t,
        appID: String?,
        canReadContent: Bool,
        screenIndex: Int?,
        displayRole: WorkspaceTopology.DisplayRole?
    ) {
        guard canReadContent else {
            return
        }

        let keyboardIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        guard keyboardIdle <= 6 else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastWritingContextAt) >= 5 else {
            return
        }

        guard let context = ActiveWindowReader.focusedWindowContext(
            processID: processID,
            appID: appID,
            appName: focus.appName,
            screenIndex: screenIndex,
            displayRole: displayRole
        ) else {
            return
        }

        guard context.hasTextualFocus else {
            return
        }

        let key = context.writingIdentityKey
        guard key != lastWritingContextKey else {
            lastWritingContextAt = now
            return
        }

        lastWritingContextKey = key
        lastWritingContextAt = now
        handler?(.writingContext(context))
    }

    private func emitInputActivity() {
        let keyboardIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let mouseIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let clickIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        let secondsSinceInput = min(keyboardIdle, mouseIdle, clickIdle)
        let mouseScreenIndex = Self.currentMouseScreenIndex()
        let mouseDisplayRole = mouseScreenIndex.map { topology.displayRole(for: $0) }

        handler?(
            .inputActivity(
                InputActivitySnapshot(
                    secondsSinceKeyboard: keyboardIdle,
                    secondsSinceMouseMove: mouseIdle,
                    secondsSinceClick: clickIdle,
                    secondsSinceAnyInput: secondsSinceInput,
                    mouseScreenIndex: mouseScreenIndex,
                    mouseDisplayRole: mouseDisplayRole
                )
            )
        )
    }

    private static func currentMouseScreenIndex() -> Int? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.firstIndex { $0.frame.contains(location) }
    }
}

enum SensorEvent {
    case displayInventory([DisplaySnapshot])
    case appFocus(AppFocusSnapshot)
    case inputActivity(InputActivitySnapshot)
    case screenContext(ScreenContextSnapshot)
    case writingContext(ScreenContextSnapshot)
}

struct DisplaySnapshot {
    let index: Int
    let localizedName: String
    let frame: CGRect
    let visibleFrame: CGRect
    let backingScaleFactor: CGFloat
    let role: WorkspaceTopology.DisplayRole
}

struct AppFocusSnapshot {
    let appID: String?
    let appName: String
    let processID: pid_t
    let windowTitle: String?
    let screenIndex: Int?
    let displayRole: WorkspaceTopology.DisplayRole?
    let contentAllowed: Bool

    var identityKey: String {
        [
            appID ?? "unknown",
            appName,
            windowTitle ?? "no-title",
            screenIndex.map(String.init) ?? "no-screen"
        ].joined(separator: "|")
    }
}

struct InputActivitySnapshot {
    let secondsSinceKeyboard: CFTimeInterval
    let secondsSinceMouseMove: CFTimeInterval
    let secondsSinceClick: CFTimeInterval
    let secondsSinceAnyInput: CFTimeInterval
    let mouseScreenIndex: Int?
    let mouseDisplayRole: WorkspaceTopology.DisplayRole?

    init(
        secondsSinceKeyboard: CFTimeInterval,
        secondsSinceMouseMove: CFTimeInterval,
        secondsSinceClick: CFTimeInterval,
        secondsSinceAnyInput: CFTimeInterval,
        mouseScreenIndex: Int? = nil,
        mouseDisplayRole: WorkspaceTopology.DisplayRole? = nil
    ) {
        self.secondsSinceKeyboard = secondsSinceKeyboard
        self.secondsSinceMouseMove = secondsSinceMouseMove
        self.secondsSinceClick = secondsSinceClick
        self.secondsSinceAnyInput = secondsSinceAnyInput
        self.mouseScreenIndex = mouseScreenIndex
        self.mouseDisplayRole = mouseDisplayRole
    }
}

struct ScreenContextSnapshot {
    let appID: String?
    let appName: String
    let windowTitle: String?
    let windowRole: String?
    let document: String?
    let focusedElementRole: String?
    let focusedElementTitle: String?
    let focusedElementValue: String?
    let selectedText: String?
    let screenIndex: Int?
    let displayRole: WorkspaceTopology.DisplayRole?
    let confidence: Double

    var identityKey: String {
        [
            appID ?? "unknown",
            windowTitle ?? "",
            document ?? "",
            focusedElementRole ?? "",
            focusedElementTitle ?? "",
            focusedElementValue ?? "",
            selectedText ?? ""
        ].joined(separator: "|")
    }
}

enum ActiveWindowReader {
    static func focusedWindowTitle(processID: pid_t) -> String? {
        guard let window = focusedWindow(processID: processID) else {
            return nil
        }

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    static func focusedWindowScreenIndex(processID: pid_t) -> Int? {
        guard
            let window = focusedWindow(processID: processID),
            let position = windowPoint(window, attribute: kAXPositionAttribute),
            let size = windowSize(window)
        else {
            return nil
        }

        let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        return NSScreen.screens.firstIndex { $0.frame.contains(center) }
    }

    static func focusedWindowContext(
        processID: pid_t,
        appID: String?,
        appName: String,
        screenIndex: Int?,
        displayRole: WorkspaceTopology.DisplayRole?
    ) -> ScreenContextSnapshot? {
        guard let window = focusedWindow(processID: processID) else {
            return nil
        }

        let app = AXUIElementCreateApplication(processID)
        let focusedElement = axElement(app, attribute: kAXFocusedUIElementAttribute)
        let windowTitle = stringAttribute(window, kAXTitleAttribute)
        let secureElement = isSecureElement(focusedElement)
        let focusedElementValue = secureElement
            ? nil
            : sanitizeText(
                PrivacyRedactor.redact(stringAttribute(focusedElement, kAXValueAttribute)),
                maxLength: 500
            )
        let selectedText = secureElement
            ? nil
            : sanitizeText(
                PrivacyRedactor.redact(stringAttribute(focusedElement, kAXSelectedTextAttribute)),
                maxLength: 500
            )

        let context = ScreenContextSnapshot(
            appID: appID,
            appName: appName,
            windowTitle: sanitizeText(PrivacyRedactor.redact(windowTitle), maxLength: 240),
            windowRole: stringAttribute(window, kAXRoleAttribute),
            document: sanitizeText(PrivacyRedactor.redact(stringAttribute(window, kAXDocumentAttribute)), maxLength: 300),
            focusedElementRole: stringAttribute(focusedElement, kAXRoleAttribute),
            focusedElementTitle: sanitizeText(
                PrivacyRedactor.redact(stringAttribute(focusedElement, kAXTitleAttribute)),
                maxLength: 240
            ),
            focusedElementValue: focusedElementValue,
            selectedText: selectedText,
            screenIndex: screenIndex,
            displayRole: displayRole,
            confidence: selectedText == nil && focusedElementValue == nil ? 0.65 : 0.85
        )

        return context.isEmpty ? nil : context
    }

    private static func focusedWindow(processID: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(processID)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        guard
            result == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func axElement(_ element: AXUIElement?, attribute: String) -> AXUIElement? {
        guard let element else {
            return nil
        }

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard
            result == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(_ element: AXUIElement?, _ attribute: String) -> String? {
        guard let element else {
            return nil
        }

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }

        if CFGetTypeID(value) == CFStringGetTypeID() {
            return value as? String
        }

        if CFGetTypeID(value) == CFURLGetTypeID(), let url = value as? URL {
            return url.path
        }

        return nil
    }

    private static func isSecureElement(_ element: AXUIElement?) -> Bool {
        let haystack = [
            stringAttribute(element, kAXRoleAttribute),
            stringAttribute(element, kAXSubroleAttribute),
            stringAttribute(element, kAXDescriptionAttribute),
            stringAttribute(element, kAXTitleAttribute)
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        return haystack.contains("secure")
            || haystack.contains("password")
            || haystack.contains("passcode")
    }

    private static func sanitizeText(_ value: String?, maxLength: Int) -> String? {
        guard var value else {
            return nil
        }

        value = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while value.contains("  ") {
            value = value.replacingOccurrences(of: "  ", with: " ")
        }

        guard !value.isEmpty else {
            return nil
        }

        if value.count > maxLength {
            let index = value.index(value.startIndex, offsetBy: maxLength)
            return String(value[..<index]) + "..."
        }

        return value
    }

    private static func windowPoint(_ window: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, attribute as CFString, &value)
        guard
            result == .success,
            let axValue = value,
            CFGetTypeID(axValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue((axValue as! AXValue), .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private static func windowSize(_ window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value)
        guard
            result == .success,
            let axValue = value,
            CFGetTypeID(axValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue((axValue as! AXValue), .cgSize, &size) else {
            return nil
        }
        return size
    }
}

private extension WorkspaceTopology {
    func displayRole(for index: Int) -> DisplayRole {
        guard displays.indices.contains(index) else {
            return .unknown
        }
        return displays[index].role
    }
}

extension Array where Element == DisplaySnapshot {
    var eventPayload: [String: String] {
        var payload: [String: String] = ["count": "\(count)"]
        for display in self {
            let prefix = "display_\(display.index)"
            payload["\(prefix)_name"] = display.localizedName
            payload["\(prefix)_role"] = display.role.rawValue
            payload["\(prefix)_frame"] = "\(Int(display.frame.origin.x)),\(Int(display.frame.origin.y)),\(Int(display.frame.width)),\(Int(display.frame.height))"
            payload["\(prefix)_scale"] = String(format: "%.2f", display.backingScaleFactor)
        }
        return payload
    }
}

extension AppFocusSnapshot {
    var eventPayload: [String: String] {
        var payload: [String: String] = [
            "app_name": appName,
            "pid": "\(processID)",
            "content_allowed": contentAllowed ? "true" : "false",
            "accessibility_window_title_available": windowTitle == nil ? "false" : "true"
        ]
        if let appID {
            payload["app_id"] = appID
        }
        if let windowTitle, !windowTitle.isEmpty {
            payload["window_title"] = windowTitle
        }
        if let screenIndex {
            payload["screen_index"] = "\(screenIndex)"
        }
        if let displayRole {
            payload["display_role"] = displayRole.rawValue
        }
        return payload
    }
}

extension InputActivitySnapshot {
    var eventPayload: [String: String] {
        var payload = [
            "seconds_since_keyboard": String(format: "%.1f", secondsSinceKeyboard),
            "seconds_since_mouse_move": String(format: "%.1f", secondsSinceMouseMove),
            "seconds_since_click": String(format: "%.1f", secondsSinceClick),
            "seconds_since_any_input": String(format: "%.1f", secondsSinceAnyInput)
        ]
        if let mouseScreenIndex {
            payload["mouse_screen_index"] = "\(mouseScreenIndex)"
        }
        if let mouseDisplayRole {
            payload["mouse_display_role"] = mouseDisplayRole.rawValue
        }
        return payload
    }
}

extension ScreenContextSnapshot {
    var isEmpty: Bool {
        [
            windowTitle,
            windowRole,
            document,
            focusedElementRole,
            focusedElementTitle,
            focusedElementValue,
            selectedText
        ].allSatisfy { ($0 ?? "").isEmpty }
    }

    var hasTextualFocus: Bool {
        guard let value = focusedElementValue, !value.isEmpty else {
            return selectedText?.isEmpty == false
        }

        let role = (focusedElementRole ?? "").lowercased()
        return role.contains("text")
            || role.contains("area")
            || role.contains("combo")
            || value.count >= 8
    }

    var writingIdentityKey: String {
        [
            appID ?? "unknown",
            focusedElementRole ?? "",
            focusedElementTitle ?? "",
            focusedElementValue ?? "",
            selectedText ?? ""
        ].joined(separator: "|")
    }

    var eventPayload: [String: String] {
        var payload: [String: String] = [
            "app_name": appName,
            "content_source": "accessibility"
        ]
        if let appID {
            payload["app_id"] = appID
        }
        if let windowTitle {
            payload["window_title"] = windowTitle
        }
        if let windowRole {
            payload["window_role"] = windowRole
        }
        if let document {
            payload["document"] = document
        }
        if let focusedElementRole {
            payload["focused_element_role"] = focusedElementRole
        }
        if let focusedElementTitle {
            payload["focused_element_title"] = focusedElementTitle
        }
        if let focusedElementValue {
            payload["focused_element_value"] = focusedElementValue
        }
        if let selectedText {
            payload["selected_text"] = selectedText
        }
        if let screenIndex {
            payload["screen_index"] = "\(screenIndex)"
        }
        if let displayRole {
            payload["display_role"] = displayRole.rawValue
        }
        return payload
    }
}
