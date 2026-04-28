import AppKit
import SwiftUI

// MARK: - Menu row with NSSwitch (native on/off control)

/// Full-width menu row that draws the blue selection highlight and hosts a label + `NSSwitch`.
private final class QuickToggleMenuRowView: NSView {
    let toggle: NSSwitch
    private let label: NSTextField
    private let stack: NSStackView

    init(title: String) {
        label = NSTextField(labelWithString: title)
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 1
        label.cell?.lineBreakMode = .byTruncatingTail

        toggle = NSSwitch()
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stack = NSStackView(views: [label, spacer, toggle])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override var intrinsicContentSize: NSSize {
        let h = max(26, stack.fittingSize.height)
        return NSSize(width: 272, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        if enclosingMenuItem?.isHighlighted == true {
            NSColor.selectedContentBackgroundColor.setFill()
            dirtyRect.fill()
        }
    }
}

/// Manages the menu bar item and the configurator panel window.
/// The panel is kept alive after close (isReleasedWhenClosed = false)
/// so reopening is instant and state is preserved.
@MainActor
class AppMenuDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var panel: ConfigWindow!
    private var menu: NSMenu!

    private var windowsSwitch: NSSwitch!
    private var dockSwitch: NSSwitch!
    private var squircleSwitch: NSSwitch!

    /// Avoid treating programmatic state updates as user edits.
    private var isSyncingQuickToggleSwitches = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // ── Menu bar icon ──────────────────────────────────────────
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bandage",
                                           accessibilityDescription: "Apple Sharpener")

        // ── Menu ───────────────────────────────────────────────────
        menu = NSMenu()
        menu.delegate = self

        menu.addItem(withTitle: "Restart Apple Sharpener",
                     action: #selector(restartSharpener), keyEquivalent: "r").target = self
        menu.addItem(.separator())

        let cfg = SharpenerConfig.load()

        // Quick Toggles submenu (native switches)
        let toggleParent = NSMenuItem(title: "Quick Toggles", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.delegate = self
        sub.minimumWidth = 280

        windowsSwitch = addQuickToggle(to: sub, title: "Windows Module",
                                       isOn: cfg.windows.enabled,
                                       action: #selector(windowsSwitchChanged(_:)))
        dockSwitch = addQuickToggle(to: sub, title: "Dock Module",
                                    isOn: cfg.dock.enabled,
                                    action: #selector(dockSwitchChanged(_:)))
        squircleSwitch = addQuickToggle(to: sub, title: "Squircle Corners",
                                        isOn: cfg.globalSquircle,
                                        action: #selector(squircleSwitchChanged(_:)))

        toggleParent.submenu = sub
        menu.addItem(toggleParent)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Settings…",
                     action: #selector(showPanel), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "About Apple Sharpener",
                     action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Report Bug",
                     action: #selector(reportBug), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit",
                     action: #selector(quit), keyEquivalent: "q").target = self

        statusItem.menu = menu

        // ── Configurator panel (created once, never released) ──────
        buildPanel()

        // Enable sharpener on launch
        cli("on")
    }

    private func addQuickToggle(to sub: NSMenu, title: String, isOn: Bool, action: Selector) -> NSSwitch {
        let row = QuickToggleMenuRowView(title: title)
        row.toggle.state = isOn ? .on : .off
        row.toggle.target = self
        row.toggle.action = action
        let item = NSMenuItem()
        item.view = row
        sub.addItem(item)
        return row.toggle
    }

    // MARK: - Panel construction
    private func buildPanel() {
        let rootView = ConfiguratorView(delegate: self)
            .environment(\.colorScheme, .dark)

        let host = NonMovableHostingView(rootView: rootView)
        host.sizingOptions = [.minSize, .standardBounds]

        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        panel = ConfigWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
            styleMask: style,
            backing: NSWindow.BackingStoreType.buffered, defer: false)
        panel.title = "Apple Sharpener Configurator"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
        panel.center()

        // Hide min/zoom buttons
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden        = true
    }

    // MARK: - Panel show/hide
    @objc func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu delegate
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard windowsSwitch != nil, dockSwitch != nil, squircleSwitch != nil else { return }

        let cfg = SharpenerConfig.load()
        isSyncingQuickToggleSwitches = true
        defer { isSyncingQuickToggleSwitches = false }

        windowsSwitch.state = cfg.windows.enabled ? .on : .off
        dockSwitch.state = cfg.dock.enabled ? .on : .off
        squircleSwitch.state = cfg.globalSquircle ? .on : .off
    }

    // MARK: - CLI helpers
    func cli(_ args: String...) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/local/bin/sharpener")
        p.arguments = args
        try? p.run()
    }

    func kickstartHelper() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["kickstart", "-k", "gui/\(getuid())/com.aspauldingcode.sharpener.helper"]
        try? p.run()
    }

    // MARK: - Actions
    @objc func restartSharpener() {
        cli("off")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.cli("on") }
    }

    /// Persists via the same path as the Settings UI (`config.kdl` + `AppleSharpener_*` CF prefs + distributed notification).
    private func applyQuickToggle(apply: (ConfigModel) -> Void) {
        guard !isSyncingQuickToggleSwitches else { return }
        let model = ConfigModel()
        model.reload()
        apply(model)
        model.save()
    }

    @objc func windowsSwitchChanged(_ sender: NSSwitch) {
        let on = (sender.state == .on)
        applyQuickToggle { $0.windowsEnabled = on }
    }

    @objc func dockSwitchChanged(_ sender: NSSwitch) {
        let on = (sender.state == .on)
        applyQuickToggle { $0.dockEnabled = on }
    }

    @objc func squircleSwitchChanged(_ sender: NSSwitch) {
        let on = (sender.state == .on)
        applyQuickToggle { $0.globalSquircle = on }
    }

    @objc func showAbout() {
        let a = NSAlert()
        a.messageText      = "Apple Sharpener"
        a.informativeText  = "Created by Alex Spaulding (@aspauldingcode).\n\nSystem-wide tweak to customize window and dock corner radius, with squircle support."
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "GitHub")
        a.addButton(withTitle: "Ko-Fi")
        NSApp.activate(ignoringOtherApps: true)
        let r = a.runModal()
        if r == .alertSecondButtonReturn { open("https://github.com/aspauldingcode/apple-sharpener") }
        else if r == .alertThirdButtonReturn { open("https://ko-fi.com/aspauldingcode") }
    }
    @objc func reportBug() { open("https://github.com/aspauldingcode/apple-sharpener/issues/new") }
    @objc func quit()      { cli("off"); NSApp.terminate(nil) }

    private func open(_ url: String) { NSWorkspace.shared.open(URL(string: url)!) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Configurator Window subclass
class ConfigWindow: NSWindow {
    override init(contentRect: NSRect,
                  styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType,
                  defer flag: Bool) {
        super.init(contentRect: contentRect,
                   styleMask: style,
                   backing: backingStoreType,
                   defer: flag)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden        = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Hosting View
class NonMovableHostingView<Content: View>: NSHostingView<Content> {
    // Normal hosting view, letting the standard title bar handle dragging.
}
