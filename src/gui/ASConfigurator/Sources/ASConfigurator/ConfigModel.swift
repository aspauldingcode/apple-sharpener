/**
 * Apple Sharpener: Configurator View Model
 *
 * Coordinates state between the SwiftUI views and the underlying
 * SharpenerConfig data model. Handles real-time synchronization with
 * the background daemon and CLI notifications.
 */

import SwiftUI
import Foundation
import Combine
import KDL

@_silgen_name("notify_post")
@discardableResult
private func notify_post(_ name: UnsafePointer<CChar>) -> Int32

@_silgen_name("notify_set_state")
@discardableResult
private func notify_set_state(_ token: Int32, _ state: UInt64) -> Int32

@_silgen_name("notify_register_check")
@discardableResult
private func notify_register_check(_ name: UnsafePointer<CChar>, _ token: UnsafeMutablePointer<Int32>) -> Int32

private let NOTIFY_STATUS_OK: Int32 = 0

// MARK: - AppRuleModel
struct AppRuleModel: Equatable, Identifiable, Codable {
    var id = UUID()
    var bundleId: String
    
    var enabled:          Bool? = nil
    var radius:           Int?  = nil
    var squircle:         Bool? = nil
    var squircleExponent: Double? = nil
    var shadows:          Bool? = nil
    var borders:          Bool? = nil
    var borderWidth:      Double? = nil
    var borderColorActive: String? = nil
    var borderColorInactive: String? = nil
    
    // Per-app module overrides
    struct ModuleOverride: Equatable, Codable {
        var mode: String = "inherit" // "square" or "default" or "inherit"
    }
    
    struct TrafficLightOverride: Equatable, Codable {
        var mode: String = "inherit" // "square" or "default" or "inherit"
    }
    
    var trafficLights = TrafficLightOverride()
    var sidebar       = ModuleOverride()
    var toolbar       = ModuleOverride()
    init(bundleId: String) { self.bundleId = bundleId }

    init(_ r: SharpenerAppRule) {
        bundleId = r.bundleId
        enabled = r.enabled
        radius = r.settings.radius
        squircle = r.settings.squircle
        squircleExponent = r.settings.squircleExponent
        shadows = r.settings.shadows
        borders = r.settings.borders
        borderWidth = r.settings.borderWidth
        borderColorActive = r.settings.borderColorActive
        borderColorInactive = r.settings.borderColorInactive
        
        if let tl = r.trafficLights {
            trafficLights.mode = tl
        }
        if let sb = r.sidebar {
            sidebar.mode = sb
        }
        if let tb = r.toolbar {
            toolbar.mode = tb
        }
    }

    func toSharpenerRule() -> SharpenerAppRule {
        let r = SharpenerAppRule(bundleId: bundleId)
        r.enabled = enabled
        r.settings.radius = radius
        r.settings.squircle = squircle
        r.settings.squircleExponent = squircleExponent
        r.settings.shadows = shadows
        r.settings.borders = borders
        r.settings.borderWidth = borderWidth
        r.settings.borderColorActive = borderColorActive
        r.settings.borderColorInactive = borderColorInactive
        
        if trafficLights.mode != "inherit" {
            r.trafficLights = trafficLights.mode
        }
        if sidebar.mode != "inherit" {
            r.sidebar = sidebar.mode
        }
        if toolbar.mode != "inherit" {
            r.toolbar = toolbar.mode
        }
        
        return r
    }
}

// MARK: - ConfigModel
@MainActor
class ConfigModel: ObservableObject {
    @Published var enabled: Bool = true

    /// Incremented after each successful `config.kdl` write so the Config Editor can reload from disk.
    @Published private(set) var configFileGeneration: UInt = 0

    /// Prevents `onChange` handlers from triggering a `save()` loop when the model is being updated from disk.
    private var isSyncingFromDisk = false

    /// The raw string content shown in the Config Editor tab. Hoisted here so it persists across tab switches.
    @Published var editorText: String = ""

    /// Coalesces slider / color-drag saves so we do not rewrite `config.kdl`, sync prefs, and post notifications on every tick (reduces stutter and flashing).
    private var debouncedSaveTask: Task<Void, Never>?

    /// After a valid `config.kdl` is written from the raw editor, refresh the structured model and listeners (same outcome as the former “Format and Apply”).
    @MainActor
    func adoptDiskConfigAfterExternalWrite() {
        // Increment generation first so the editor knows this was an intentional write
        configFileGeneration += 1
        if reload() {
            syncRuntimeMirrors()
        }
    }

    /// Use for sliders and color fields; calls `save()` once after updates settle (~320ms), or immediately if another `save()` runs first.
    func saveDebounced() {
        guard !isSyncingFromDisk else { return }
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard let self, !Task.isCancelled else { return }
            self.debouncedSaveTask = nil
            self.save()
        }
    }

    /// Parses and saves the current `editorText` buffer to disk, then reloads the structured model.
    /// Used when switching away from the editor tab or after a debounce timeout.
    func commitFormattedKDL() {
        var toParse = editorText.trimmingCharacters(in: .whitespacesAndNewlines)
        if toParse.isEmpty { return }
        if toParse.hasPrefix("\u{FEFF}") { toParse = String(toParse.dropFirst()) }
        toParse = SharpenerConfig.normalizeLegacyKDLChildLines(toParse)
        
        guard let doc = try? KDL.parseDocument(toParse), doc["sharpener"] != nil else {
            NSLog("ASConfigurator: Editor commit failed — invalid KDL or missing 'sharpener' block")
            return 
        }
        
        let formatted = doc.description
        editorText = formatted // Update buffer with canonical form
        
        if SharpenerConfig.writeKDLAtomically(formatted) {
            adoptDiskConfigAfterExternalWrite()
        }
    }

    // Global (Master)
    @Published var globalRadius:           Int?    = 14
    @Published var globalSquircle:         Bool   = true
    @Published var globalSquircleExponent: Double = 4.0
    @Published var globalShadows:          Bool   = true
    @Published var globalBorders:          Bool   = false
    @Published var globalBorderWidth:      Double = 4.0
    @Published var globalBorderColorActive: String = NSColor.controlAccentColor.hexARGBString
    @Published var globalBorderColorInactive: String = "0xFF808080"
    
    var systemAccentColorHex: String { NSColor.controlAccentColor.hexARGBString }

    // Windows Module
    @Published var windowsEnabled: Bool = true
    @Published var windowsRadius: Int? = nil
    @Published var windowsSquircle: Bool? = nil
    @Published var windowsSquircleExponent: Double? = nil
    @Published var windowsShadows: Bool? = nil
    @Published var windowsBorders: Bool? = nil
    @Published var windowsBorderWidth: Double? = nil
    @Published var windowsBorderColorActive: String? = nil
    @Published var windowsBorderColorInactive: String? = nil

    // Windows -> Traffic Lights
    @Published var trafficLightsMode: String = "default" // square, default

    // Windows -> Sidebar
    @Published var sidebarMode: String = "default"

    // Windows -> Toolbar
    @Published var toolbarMode: String = "default"

    // Dock Module
    @Published var dockEnabled: Bool = true
    @Published var dockRadius: Int? = nil
    @Published var dockSquircle: Bool? = nil
    @Published var dockSquircleExponent: Double? = nil
    @Published var dockBorders: Bool? = nil
    @Published var dockBorderWidth: Double? = nil
    @Published var dockBorderColorActive: String? = nil
    @Published var dockBorderColorInactive: String? = nil

    // Rules
    @Published var rules: [AppRuleModel] = []

    private var anyCancellables = Set<AnyCancellable>()
    private var isPerformingSave = false
    private var _configFileSource: DispatchSourceFileSystemObject?

    init() {
        _ = reload()
        setupConfigFileWatcher()
    }

    /// Watch config.kdl for changes from external tools (CLI, manual edits).
    /// The GUI should NOT reload on `modules.update` notifications — those are
    /// for the dylib/Dock. We only reload when the file itself changes on disk.
    private func setupConfigFileWatcher() {
        let path = SharpenerConfig.configPath
        // Create the file if it doesn't exist so we can open an fd for kqueue
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
        }
        guard let fd = FileHandle(forReadingAtPath: path) else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd.fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            guard !self.isPerformingSave && self.debouncedSaveTask == nil else { return }
            NSLog("ASConfigurator: config.kdl changed on disk — reloading UI")
            if self.reload() {
                self.configFileGeneration += 1
            }
        }
        source.setCancelHandler { try? fd.close() }
        source.resume()
        self._configFileSource = source
    }

    func reload() -> Bool {
        isSyncingFromDisk = true
        defer { isSyncingFromDisk = false }
        let c: SharpenerConfig
        switch SharpenerConfig.read() {
        case .ok(let loaded):
            c = loaded
        case .fileMissing:
            c = SharpenerConfig()
        case .invalidDocument:
            NSLog("ASConfigurator: \(SharpenerConfig.configPath) exists but is not valid KDL or lacks a `sharpener` node; UI state unchanged. Fix the file or restore \(SharpenerConfig.configBackupPath).")
            return false
        }
        enabled = c.enabled

        globalRadius           = c.globalRadius
        globalSquircle         = c.globalSquircle
        globalSquircleExponent = c.globalSquircleExponent
        globalShadows          = c.globalShadows
        globalBorders          = c.globalBorders
        globalBorderWidth      = c.globalBorderWidth
        globalBorderColorActive = c.globalBorderColorActive
        globalBorderColorInactive = c.globalBorderColorInactive
        
        // Windows
        windowsEnabled = c.windows.enabled
        windowsRadius = c.windows.settings.radius
        windowsSquircle = c.windows.settings.squircle
        windowsSquircleExponent = c.windows.settings.squircleExponent
        windowsShadows = c.windows.settings.shadows
        windowsBorders = c.windows.settings.borders
        windowsBorderWidth = c.windows.settings.borderWidth
        windowsBorderColorActive = c.windows.settings.borderColorActive
        windowsBorderColorInactive = c.windows.settings.borderColorInactive
        
        if let tl = c.windows.trafficLights {
            trafficLightsMode = tl
        }
        
        if let sb = c.windows.sidebar {
            sidebarMode = sb
        }

        if let tb = c.windows.toolbar {
            toolbarMode = tb
        }
        
        // Dock
        dockEnabled = c.dock.enabled
        dockRadius = c.dock.settings.radius
        dockSquircle = c.dock.settings.squircle
        dockSquircleExponent = c.dock.settings.squircleExponent
        dockBorders = c.dock.settings.borders
        dockBorderWidth = c.dock.settings.borderWidth
        dockBorderColorActive = c.dock.settings.borderColorActive
        dockBorderColorInactive = c.dock.settings.borderColorInactive
        
        rules = c.rules.map { AppRuleModel($0) }
        
        // Update the raw editor buffer if we aren't currently editing it
        if let diskText = try? String(contentsOfFile: SharpenerConfig.configPath, encoding: .utf8) {
            editorText = diskText
        }
        
        return true
    }

    func save() {
        guard !isSyncingFromDisk else { return }
        isPerformingSave = true
        defer { isPerformingSave = false }
        
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        clampRadiusFields()
        let c: SharpenerConfig
        switch SharpenerConfig.read() {
        case .ok(let loaded):
            c = loaded
        case .fileMissing:
            c = SharpenerConfig()
        case .invalidDocument:
            if SharpenerConfig.patchRootEnabledLineAfterSharpener(enabled: enabled) {
                configFileGeneration += 1
                NSLog("ASConfigurator: config had parse errors — updated root enabled=\(enabled) only. Repair \(SharpenerConfig.configPath) for full GUI saves.")
                syncRuntimeMirrors()
            } else {
                NSLog("ASConfigurator: save skipped — \(SharpenerConfig.configPath) is unreadable or invalid; could not patch root enabled. Fix the file or restore \(SharpenerConfig.configBackupPath).")
            }
            return
        }
        c.enabled = enabled
        c.globalRadius = globalRadius
        c.globalSquircle = globalSquircle
        c.globalSquircleExponent = globalSquircleExponent
        c.globalShadows = globalShadows
        c.globalBorders = globalBorders
        c.globalBorderWidth = globalBorderWidth
        c.globalBorderColorActive = globalBorderColorActive
        c.globalBorderColorInactive = globalBorderColorInactive
        
        // Windows
        c.windows.enabled = windowsEnabled
        c.windows.settings.radius = windowsRadius
        c.windows.settings.squircle = windowsSquircle
        c.windows.settings.squircleExponent = windowsSquircleExponent
        c.windows.settings.shadows = windowsShadows
        c.windows.settings.borders = windowsBorders
        c.windows.settings.borderWidth = windowsBorderWidth
        c.windows.settings.borderColorActive = windowsBorderColorActive
        c.windows.settings.borderColorInactive = windowsBorderColorInactive
        
        c.windows.trafficLights = trafficLightsMode
        c.windows.sidebar = sidebarMode
        c.windows.toolbar = toolbarMode
        
        // Dock
        c.dock.enabled = dockEnabled
        c.dock.settings.radius = dockRadius
        c.dock.settings.squircle = dockSquircle
        c.dock.settings.squircleExponent = dockSquircleExponent
        c.dock.settings.borders = dockBorders
        c.dock.settings.borderWidth = dockBorderWidth
        c.dock.settings.borderColorActive = dockBorderColorActive
        c.dock.settings.borderColorInactive = dockBorderColorInactive
        
        c.rules = rules.map { $0.toSharpenerRule() }
        c.save()
        configFileGeneration += 1
        syncRuntimeMirrors()
    }

    /// Mirror the current UI model to CFPreferences, UserDefaults suite, and notify — without writing `config.kdl`.
    func syncRuntimeMirrors() {
        clampRadiusFields()
        var rulesArray: [[String: Any]] = []
        for rule in rules {
            var dict: [String: Any] = [:]
            dict["bundleId"] = rule.bundleId
            if let e = rule.enabled { dict["enabled"] = e }
            if let r = rule.radius { dict["radius"] = r }
            if let sq = rule.squircle { dict["squircle"] = sq }
            if let sqe = rule.squircleExponent { dict["squircleExponent"] = sqe }
            if let sh = rule.shadows { dict["shadows"] = sh }
            if let b = rule.borders { dict["borders"] = b }
            if let bw = rule.borderWidth { dict["borderWidth"] = bw }
            if let bca = rule.borderColorActive { dict["borderColorActive"] = bca }
            if let bci = rule.borderColorInactive { dict["borderColorInactive"] = bci }
            
            if rule.trafficLights.mode != "inherit" { dict["traffic_lights"] = rule.trafficLights.mode }
            if rule.sidebar.mode != "inherit" { dict["sidebar"] = rule.sidebar.mode }
            if rule.toolbar.mode != "inherit" { dict["toolbar"] = rule.toolbar.mode }
            
            rulesArray.append(dict)
        }
        
        // Effective booleans match `sharpener on` / `off` / `toggle`: master off
        // forces windows, dock, and squircle runtime off (dylib prefers module keys).
        let runtimeWindowsOn = enabled && windowsEnabled
        let runtimeDockOn = enabled && dockEnabled
        let runtimeSquircleOn = enabled && globalSquircle

        // Mirror to Global Domain for Sandboxed Apps (Safari, Chess, Word, etc.)
        let globalSync: [String: Any?] = [
            "enabled": enabled,
            "radius": globalRadius,
            "squircle_enabled": runtimeSquircleOn,
            "squircle_exponent": globalSquircleExponent,
            "global_borders": globalBorders,
            "global_border_width": globalBorderWidth,
            "global_border_color_active": globalBorderColorActive,
            "global_border_color_inactive": globalBorderColorInactive,
            "global_shadows": globalShadows,
            "windows_enabled": runtimeWindowsOn,
            "windows_radius": windowsRadius,
            "windows_squircle": windowsSquircle,
            "windows_squircle_exponent": windowsSquircleExponent,
            "windows_shadows": windowsShadows,
            "windows_borders": windowsBorders,
            "windows_border_width": windowsBorderWidth,
            "windows_border_color_active": windowsBorderColorActive,
            "windows_border_color_inactive": windowsBorderColorInactive,
            "traffic_lights_mode": trafficLightsMode,
            "sidebar_mode": sidebarMode,
            "toolbar_mode": toolbarMode,
            "dock_enabled": runtimeDockOn,
            "dock_radius": dockRadius,
            "dock_squircle": dockSquircle,
            "dock_squircle_exponent": dockSquircleExponent,
            "dock_borders": dockBorders,
            "dock_border_width": dockBorderWidth,
            "dock_border_color_active": dockBorderColorActive,
            "dock_border_color_inactive": dockBorderColorInactive,
            "rules": rulesArray
        ]
        
        for (key, value) in globalSync {
            if let v = value {
                CFPreferencesSetValue("AppleSharpener_\(key)" as CFString, v as CFPropertyList, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            } else {
                CFPreferencesSetValue("AppleSharpener_\(key)" as CFString, nil, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            }
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        // Same suite + notify path as `sharpener -d off` / `-w off` (CLI writes
        // here; without this, dock-only toggle relied on CF alone and drifted).
        if let suite = UserDefaults(suiteName: "com.aspauldingcode.apple_sharpener") {
            for (key, opt) in globalSync {
                if let v = opt {
                    suite.set(v, forKey: key)
                } else {
                    suite.removeObject(forKey: key)
                }
            }
            suite.synchronize()
        }

        var masterTok: Int32 = 0
        if notify_register_check("com.aspauldingcode.apple_sharpener.enabled", &masterTok) == NOTIFY_STATUS_OK {
            notify_set_state(masterTok, enabled ? 1 : 0)
            notify_post("com.aspauldingcode.apple_sharpener.enabled")
        }

        var dockTok: Int32 = 0
        if notify_register_check("com.aspauldingcode.apple_sharpener.dock.enabled", &dockTok) == NOTIFY_STATUS_OK {
            notify_set_state(dockTok, runtimeDockOn ? 1 : 0)
            notify_post("com.aspauldingcode.apple_sharpener.dock.enabled")
        }

        var winTok: Int32 = 0
        if notify_register_check("com.aspauldingcode.apple_sharpener.windows.enabled", &winTok) == NOTIFY_STATUS_OK {
            notify_set_state(winTok, runtimeWindowsOn ? 1 : 0)
            notify_post("com.aspauldingcode.apple_sharpener.windows.enabled")
        }

        var sqTok: Int32 = 0
        if notify_register_check("com.aspauldingcode.apple_sharpener.squircle.enabled", &sqTok) == NOTIFY_STATUS_OK {
            notify_set_state(sqTok, runtimeSquircleOn ? 1 : 0)
            notify_post("com.aspauldingcode.apple_sharpener.squircle.enabled")
        }

        // Match CLI global `sharpener off`: poke radius notify so windows redraw immediately.
        if !enabled {
            var radTok: Int32 = 0
            if notify_register_check("com.aspauldingcode.apple_sharpener.windows.set_radius", &radTok) == NOTIFY_STATUS_OK {
                let r = max(0, windowsRadius ?? globalRadius ?? 0)
                notify_set_state(radTok, UInt64(r))
                notify_post("com.aspauldingcode.apple_sharpener.windows.set_radius")
            }
        }
        
        // Post notifications
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.aspauldingcode.apple_sharpener.modules.update"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    /// Align with CLI / dylib caps: windows (global, module, rules) ≤ 100, dock ≤ 46.
    private func clampRadiusFields() {
        globalRadius = SharpenerConfig.clampWindowsRadius(globalRadius)
        windowsRadius = SharpenerConfig.clampWindowsRadius(windowsRadius)
        dockRadius = SharpenerConfig.clampDockRadius(dockRadius)
        for i in rules.indices {
            rules[i].radius = SharpenerConfig.clampWindowsRadius(rules[i].radius)
        }
    }
}
