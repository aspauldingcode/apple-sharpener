import AppKit

// Entry point: use NSApplicationMain (avoids @main conflict with SPM's main.swift top-level code)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppMenuDelegate()
app.delegate = delegate
app.run()
