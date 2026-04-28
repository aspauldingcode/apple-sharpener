import Foundation
import AppKit
import KDL

/// Common settings structure that can be used for Global, Modules, or App Rules
struct SharpenerSettings: Codable {
    var radius: Int? = nil
    var squircle: Bool? = nil
    var squircleExponent: Double? = nil
    var shadows: Bool? = nil
    var borders: Bool? = nil
    var borderWidth: Double? = nil
    var borderColorActive: String? = nil
    var borderColorInactive: String? = nil
}

/// A module configuration (e.g. Windows, Dock) - Using class to allow recursion
class SharpenerModuleConfig: Codable {
    var enabled: Bool = true
    var settings: SharpenerSettings = SharpenerSettings()
    
    // Nested components (for Windows)
    var trafficLights: String? = nil
    var sidebar: String? = nil
    var toolbar: String? = nil

    init() {}
}

/// Data model for per-app rules
class SharpenerAppRule: Codable {
    var bundleId: String
    var enabled: Bool? = nil
    var settings: SharpenerSettings = SharpenerSettings()
    
    // Per-app module overrides
    var trafficLights: String? = nil
    var sidebar: String? = nil
    var toolbar: String? = nil

    init(bundleId: String) { self.bundleId = bundleId }
}

/// Main configuration model with unified inheritance
class SharpenerConfig {
    var enabled: Bool = true
    
    // Global concrete values
    var globalRadius: Int? = 14
    var globalSquircle: Bool = true
    var globalSquircleExponent: Double = 4.0
    var globalShadows: Bool = true
    var globalBorders: Bool = false
    var globalBorderWidth: Double = 4.0
    var globalBorderColorActive: String = NSColor.controlAccentColor.hexARGBString
    var globalBorderColorInactive: String = "0xFF808080"

    // Modules
    var windows: SharpenerModuleConfig = SharpenerModuleConfig()
    var dock: SharpenerModuleConfig = SharpenerModuleConfig()

    // Rules
    var rules: [SharpenerAppRule] = []

    static let configPath = NSHomeDirectory() + "/.config/sharpener/config.kdl"

    init() {}

    static func load() -> SharpenerConfig {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let string = String(data: data, encoding: String.Encoding.utf8),
              let doc = try? KDL.parseDocument(string) else {
            return SharpenerConfig() // Return defaults (4.0)
        }
        
        let cfg = SharpenerConfig()
        
        // Root 'sharpener' node
        if let root = doc["sharpener"] {
            cfg.enabled = root.getProperty("enabled")?.asBool() ?? root.arg("enabled")?.asBool() ?? cfg.enabled
            
            if let g = root.getChild("global") {
                cfg.globalRadius           = g.arg("radius")?.asInt() ?? cfg.globalRadius
                cfg.globalSquircle         = g.arg("squircle")?.asBool() ?? cfg.globalSquircle
                cfg.globalSquircleExponent = g.arg("squircle_exponent")?.asDouble() ?? cfg.globalSquircleExponent
                cfg.globalShadows          = g.arg("shadows")?.asBool() ?? cfg.globalShadows
                cfg.globalBorders          = g.arg("borders")?.asBool() ?? cfg.globalBorders
                cfg.globalBorderWidth      = g.arg("border_width")?.asDouble() ?? cfg.globalBorderWidth
                cfg.globalBorderColorActive = g.arg("border_color_active")?.asString() ?? cfg.globalBorderColorActive
                cfg.globalBorderColorInactive = g.arg("border_color_inactive")?.asString() ?? cfg.globalBorderColorInactive
            }
            
            if let w = root.getChild("windows") {
                cfg.windows = parseModule(w)
                cfg.windows.trafficLights = w.getProperty("traffic_lights")?.asString() ?? w.arg("traffic_lights")?.asString()
                cfg.windows.sidebar = w.getProperty("sidebar")?.asString() ?? w.arg("sidebar")?.asString()
                cfg.windows.toolbar = w.getProperty("toolbar")?.asString() ?? w.arg("toolbar")?.asString()
            }
            
            if let d = root.getChild("dock") {
                cfg.dock = parseModule(d)
            }
            
            if let rulesNode = root.getChild("rules") {
                for child in rulesNode.getChildren() where child.name == "app" {
                    guard let id = child.arguments.first?.asString() else { continue }
                    let rule = SharpenerAppRule(bundleId: id)
                    if let e = child.getProperty("enabled")?.asBool() { rule.enabled = e }
                    rule.settings = parseSettings(child)
                    
                    // Parse nested modules for this app rule
                    rule.trafficLights = child.getProperty("traffic_lights")?.asString() ?? child.arg("traffic_lights")?.asString()
                    rule.sidebar = child.getProperty("sidebar")?.asString() ?? child.arg("sidebar")?.asString()
                    rule.toolbar = child.getProperty("toolbar")?.asString() ?? child.arg("toolbar")?.asString()
                    
                    cfg.rules.append(rule)
                }
            }
        }
        
        return cfg
    }

    private static func parseModule(_ node: KDLNode) -> SharpenerModuleConfig {
        let m = SharpenerModuleConfig()
        m.enabled = node.getProperty("enabled")?.asBool() ?? node.arg("enabled")?.asBool() ?? m.enabled
        m.settings = parseSettings(node)
        return m
    }

    private static func parseSettings(_ node: KDLNode) -> SharpenerSettings {
        var s = SharpenerSettings()
        s.radius            = node.arg("radius")?.asInt()
        s.squircle          = node.arg("squircle")?.asBool()
        s.squircleExponent  = node.arg("squircle_exponent")?.asDouble()
        s.shadows           = node.arg("shadows")?.asBool()
        s.borders           = node.arg("borders")?.asBool()
        s.borderWidth       = node.arg("border_width")?.asDouble()
        s.borderColorActive = node.arg("border_color_active")?.asString()
        s.borderColorInactive = node.arg("border_color_inactive")?.asString()
        return s
    }

    func save() {
        var kdl = "sharpener {\n"
        kdl += "    enabled=\(enabled)\n"
        
        kdl += "    global {\n"
        if let r = globalRadius {
            kdl += "        radius \(r)\n"
        }
        kdl += "        squircle \(globalSquircle)\n"
        kdl += "        squircle_exponent \(globalSquircleExponent)\n"
        kdl += "        shadows \(globalShadows)\n"
        kdl += "        borders \(globalBorders)\n"
        kdl += "        border_width \(globalBorderWidth)\n"
        kdl += "        border_color_active \"\(globalBorderColorActive)\"\n"
        kdl += "        border_color_inactive \"\(globalBorderColorInactive)\"\n"
        kdl += "    }\n\n"
        
        kdl += serializeModule(windows, name: "windows", indent: "    ") {
            var sub = ""
            if let t = self.windows.trafficLights { sub += "        traffic_lights \"\(t)\"\n" }
            if let s = self.windows.sidebar { sub += "        sidebar \"\(s)\"\n" }
            if let tb = self.windows.toolbar { sub += "        toolbar \"\(tb)\"\n" }
            return sub
        }
        
        kdl += serializeModule(dock, name: "dock", indent: "    ")
        
        if !rules.isEmpty {
            kdl += "    rules {\n"
            for rule in rules {
                let appHeader = "        app \"\(rule.bundleId)\""
                kdl += appHeader + " {\n"
                if let e = rule.enabled { kdl += "            enabled \(e)\n" }
                kdl += serializeSettings(rule.settings, indent: "            ")
                
                if let t = rule.trafficLights { kdl += "            traffic_lights \"\(t)\"\n" }
                if let s = rule.sidebar { kdl += "            sidebar \"\(s)\"\n" }
                if let tb = rule.toolbar { kdl += "            toolbar \"\(tb)\"\n" }
                
                kdl += "        }\n"
            }
            kdl += "    }\n"
        }
        
        kdl += "}\n"
        
        try? kdl.write(toFile: SharpenerConfig.configPath, atomically: true, encoding: String.Encoding.utf8)
    }

    private func serializeModule(_ m: SharpenerModuleConfig, name: String, indent: String, sub: (() -> String)? = nil) -> String {
        var kdl = "\(indent)\(name) {\n"
        kdl += "\(indent)    enabled=\(m.enabled)\n"
        kdl += serializeSettings(m.settings, indent: indent + "    ")
        if let s = sub?() { kdl += s }
        kdl += "\(indent)}\n\n"
        return kdl
    }

    private func serializeSettings(_ s: SharpenerSettings, indent: String) -> String {
        var kdl = ""
        if let r = s.radius  { kdl += "\(indent)radius \(r)\n" }
        if let sq = s.squircle{ kdl += "\(indent)squircle \(sq)\n" }
        if let sqe = s.squircleExponent { kdl += "\(indent)squircle_exponent \(sqe)\n" }
        if let sh = s.shadows { kdl += "\(indent)shadows \(sh)\n" }
        if let b = s.borders { kdl += "\(indent)borders \(b)\n" }
        if let bw = s.borderWidth { kdl += "\(indent)border_width \(bw)\n" }
        if let ba = s.borderColorActive { kdl += "\(indent)border_color_active \"\(ba)\"\n" }
        if let bi = s.borderColorInactive { kdl += "\(indent)border_color_inactive \"\(bi)\"\n" }
        return kdl
    }
}

// MARK: - KDL Reflection Hack
extension KDLDocument {
    subscript(name: String) -> KDLNode? {
        return getNodes().first { $0.name == name }
    }
    func getNodes() -> [KDLNode] {
        let mirror = Mirror(reflecting: self)
        return mirror.descendant("nodes") as? [KDLNode] ?? []
    }
}

extension KDLNode {
    var name: String {
        let mirror = Mirror(reflecting: self)
        return mirror.descendant("name") as? String ?? ""
    }
    var arguments: [KDLValue] {
        let mirror = Mirror(reflecting: self)
        return mirror.descendant("arguments") as? [KDLValue] ?? []
    }
    func getChildren() -> [KDLNode] {
        let mirror = Mirror(reflecting: self)
        return mirror.descendant("children") as? [KDLNode] ?? []
    }
    func getChild(_ name: String) -> KDLNode? {
        return getChildren().first { $0.name == name }
    }
    func getProperty(_ name: String) -> KDLValue? {
        let mirror = Mirror(reflecting: self)
        guard let props = mirror.descendant("properties") as? [String: KDLValue] else { return nil }
        return props[name]
    }
    func arg(_ indexOrName: String) -> KDLValue? {
        if let p = getProperty(indexOrName) { return p }
        return arguments.first
    }
}

extension KDLValue {
    func asString() -> String? { if case .string(let s, _, _) = self { return s }; return nil }
    func asInt() -> Int? {
        if case .int(let i, _, _) = self { return i }
        if case .float(let f, _, _) = self { return Int(f) }
        return nil
    }
    func asDouble() -> Double? {
        if case .float(let f, _, _) = self { return Double(f) }
        if case .int(let i, _, _) = self { return Double(i) }
        return nil
    }
    func asBool() -> Bool? { if case .bool(let b, _, _) = self { return b }; return nil }
}

extension NSColor {
    var hexARGBString: String {
        guard let rgb = self.usingColorSpace(.deviceRGB) else { return "0xFFFFFFFF" }
        let a = Int(rgb.alphaComponent * 255)
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "0x%02X%02X%02X%02X", a, r, g, b)
    }
}
