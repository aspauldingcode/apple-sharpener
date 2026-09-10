/**
 * Apple Sharpener: Configurator Entry Point
 *
 * Initializes the NSApplication and sets up the AppDelegate for the
 * Swift-based configuration GUI.
 */

import Cocoa
import SwiftUI

// Entry point: use NSApplicationMain (avoids @main conflict with SPM's main.swift top-level code)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppMenuDelegate()
app.delegate = delegate
app.run()
