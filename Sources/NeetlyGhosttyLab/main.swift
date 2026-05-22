import AppKit

// neetly-ghostty-lab — a standalone window hosting one libghostty terminal.
//
// This is the isolated Step-1 spike: it shares no code with `neetly-app`,
// so nothing here can affect the shipping app. Build + run with:
//
//     swift build --product neetly-ghostty-lab
//     .build/debug/neetly-ghostty-lab

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
