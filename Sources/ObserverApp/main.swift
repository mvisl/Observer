import AppKit

let application = NSApplication.shared
let delegate = ObserverApp()
application.delegate = delegate
application.run()
