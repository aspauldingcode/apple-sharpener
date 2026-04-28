import SwiftUI
import Foundation

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
class ConfigModel: ObservableObject {
    @Published var enabled: Bool = true

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

    init() { reload() }

    func reload() {
        let c = SharpenerConfig.load()
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
    }

    func save() {
        // Load existing config first to avoid losing data from fields not in this model
        let c = SharpenerConfig.load()
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
        
        // Save flattened rules for the dylib

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
        
        // Mirror to Global Domain for Sandboxed Apps (Safari, Chess, Word, etc.)
        let globalSync: [String: Any?] = [
            "enabled": enabled,
            "radius": globalRadius,
            "squircle_enabled": globalSquircle,
            "squircle_exponent": globalSquircleExponent,
            "global_borders": globalBorders,
            "global_border_width": globalBorderWidth,
            "global_border_color_active": globalBorderColorActive,
            "global_border_color_inactive": globalBorderColorInactive,
            "global_shadows": globalShadows,
            "windows_enabled": windowsEnabled,
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
            "dock_enabled": dockEnabled,
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
        
        // Post notifications
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.aspauldingcode.apple_sharpener.modules.update"), object: nil, userInfo: nil, deliverImmediately: true)
    }
}
