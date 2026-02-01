import AppKit

let app = NSApplication.shared
let delegate = AgentAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
