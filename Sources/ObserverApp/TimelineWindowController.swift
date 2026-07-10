import AppKit

@MainActor
final class TimelineWindowController {
    private let window: NSWindow
    private let textView = NSTextView()

    init() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 520))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        scrollView.documentView = textView

        window = NSWindow(
            contentRect: scrollView.frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Observer Timeline"
        window.contentView = scrollView
        window.center()
    }

    func show(text: String) {
        textView.string = text
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
