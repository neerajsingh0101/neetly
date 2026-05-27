import AppKit

// Set the process name so the menu bar shows "Neetly" instead of "neetly-app"
ProcessInfo.processInfo.performSelector(onMainThread: Selector(("setProcessName:")), with: "Neetly", waitUntilDone: true)

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
