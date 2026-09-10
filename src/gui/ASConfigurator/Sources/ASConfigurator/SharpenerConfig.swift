/**
 * Apple Sharpener: Configuration Data Model
 *
 * Defines the SharpenerConfig class which handles reading, writing, and
 * manipulating the KDL-based configuration file. It also provides the
 * data structures for unified inheritance of settings across global,
 * module, and per-app levels.
 */

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

/// Main configuration model with unified inheritance.
/// `enabled` is the master switch: when false it matches CLI `sharpener off` at runtime
/// (see helper gate after parsing KDL and `ConfigModel.syncRuntimeMirrors()`).
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
    static let configBackupPath = configPath + ".bak"

    /// KDL allows `name value` child lines, not `name=value` on its own line inside `{ … }`.
    /// We historically emitted `enabled=true`, which kdl-swift correctly rejects.
    static func normalizeLegacyKDLChildLines(_ source: String) -> String {
        let pattern = #"(?m)^(\s*)enabled\s*=\s*(true|false)\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return source }
        let range = NSRange(source.utf16.startIndex..<source.utf16.endIndex, in: source)
        return re.stringByReplacingMatches(in: source, options: [], range: range, withTemplate: "$1enabled $2")
    }

    private static func kdlAsciiDouble(_ value: Double) -> String {
        String(format: "%.16g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    // MARK: - Radius limits (aligned with `clitool.m` and `dock.m`)

    enum RadiusLimit {
        /// Global default, windows module, per-app window rules (`sharpener -r`, `-w`).
        static let windows: Int = 100
        /// Dock module only (`-d` / effective when inheriting global).
        static let dock: Int = 46
    }

    /// `nil` preserves inherit semantics.
    static func clampWindowsRadius(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), RadiusLimit.windows) }
    }

    static func clampDockRadius(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), RadiusLimit.dock) }
    }

    init() {}

    /// Disk read outcome: never fabricate `ok` from a broken file.
    enum ReadResult {
        case ok(SharpenerConfig)
        case fileMissing
        case invalidDocument
    }

    static func read() -> ReadResult {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: configPath, isDirectory: &isDir) {
            return .fileMissing
        }
        if isDir.boolValue { return .invalidDocument }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)), !data.isEmpty else {
            return .invalidDocument
        }
        guard let raw = String(data: data, encoding: .utf8) else { return .invalidDocument }
        let string = normalizeLegacyKDLChildLines(raw)
        guard let doc = try? KDL.parseDocument(string), doc["sharpener"] != nil else {
            return .invalidDocument
        }
        return .ok(parseDocument(doc))
    }

    /// Loads when possible; treats missing file as fresh defaults; **still returns defaults for invalid docs** (menus only — do not save based on this alone).
    static func load() -> SharpenerConfig {
        switch read() {
        case .ok(let c): return c
        case .fileMissing: return SharpenerConfig()
        case .invalidDocument: return SharpenerConfig()
        }
    }

    private static func parseDocument(_ doc: KDLDocument) -> SharpenerConfig {
        let cfg = SharpenerConfig()
        guard let root = doc["sharpener"] else { return cfg }

        cfg.enabled = root["enabled"]?.asBool() ?? root.arg("enabled")?.asBool() ?? cfg.enabled

        if let g = root.getChild("global") {
            if let raw = g.arg("radius")?.asInt() {
                cfg.globalRadius = min(max(raw, 0), RadiusLimit.windows)
            }
            cfg.globalSquircle         = g.arg("squircle")?.asBool() ?? cfg.globalSquircle
            cfg.globalSquircleExponent = g.arg("squircle_exponent")?.asDouble() ?? cfg.globalSquircleExponent
            cfg.globalShadows          = g.arg("shadows")?.asBool() ?? cfg.globalShadows
            cfg.globalBorders          = g.arg("borders")?.asBool() ?? cfg.globalBorders
            cfg.globalBorderWidth      = g.arg("border_width")?.asDouble() ?? cfg.globalBorderWidth
            cfg.globalBorderColorActive = g.arg("border_color_active")?.asString() ?? cfg.globalBorderColorActive
            cfg.globalBorderColorInactive = g.arg("border_color_inactive")?.asString() ?? cfg.globalBorderColorInactive
        }

        if let w = root.getChild("windows") {
            cfg.windows = parseModule(w, radiusMax: RadiusLimit.windows)
            cfg.windows.trafficLights = w["traffic_lights"]?.asString() ?? w.arg("traffic_lights")?.asString()
            cfg.windows.sidebar = w["sidebar"]?.asString() ?? w.arg("sidebar")?.asString()
            cfg.windows.toolbar = w["toolbar"]?.asString() ?? w.arg("toolbar")?.asString()
        }

        if let d = root.getChild("dock") {
            cfg.dock = parseModule(d, radiusMax: RadiusLimit.dock)
        }

        if let rulesNode = root.getChild("rules") {
            for child in rulesNode.getChildren() where child.name == "app" {
                guard let id = child.arguments.first?.asString() else { continue }
                let rule = SharpenerAppRule(bundleId: id)
                if let e = child["enabled"]?.asBool() { rule.enabled = e }
                rule.settings = parseSettings(child, radiusMax: RadiusLimit.windows)

                rule.trafficLights = child["traffic_lights"]?.asString() ?? child.arg("traffic_lights")?.asString()
                rule.sidebar = child["sidebar"]?.asString() ?? child.arg("sidebar")?.asString()
                rule.toolbar = child["toolbar"]?.asString() ?? child.arg("toolbar")?.asString()

                cfg.rules.append(rule)
            }
        }

        return cfg
    }

    private static func parseModule(_ node: KDLNode, radiusMax: Int) -> SharpenerModuleConfig {
        let m = SharpenerModuleConfig()
        m.enabled = node["enabled"]?.asBool() ?? node.arg("enabled")?.asBool() ?? m.enabled
        m.settings = parseSettings(node, radiusMax: radiusMax)
        return m
    }

    private static func parseSettings(_ node: KDLNode, radiusMax: Int) -> SharpenerSettings {
        var s = SharpenerSettings()
        if let r = node.arg("radius")?.asInt() {
            s.radius = min(max(r, 0), radiusMax)
        }
        s.squircle          = node.arg("squircle")?.asBool()
        s.squircleExponent  = node.arg("squircle_exponent")?.asDouble()
        s.shadows           = node.arg("shadows")?.asBool()
        s.borders           = node.arg("borders")?.asBool()
        s.borderWidth       = node.arg("border_width")?.asDouble()
        s.borderColorActive = node.arg("border_color_active")?.asString()
        s.borderColorInactive = node.arg("border_color_inactive")?.asString()
        return s
    }

    /// Writes UTF-8 KDL and mirrors backup semantics used by `save()`.
    @discardableResult
    static func writeKDLAtomically(_ kdl: String) -> Bool {
        let url = URL(fileURLWithPath: Self.configPath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let existing = try? Data(contentsOf: url), !existing.isEmpty {
            try? existing.write(to: URL(fileURLWithPath: Self.configBackupPath), options: .atomic)
        }
        guard let data = kdl.data(using: .utf8) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// When the file fails full `read()` but still contains `sharpener`, update the first root-level `enabled=` line
    /// so the global GUI toggle persists (matches `sharpener off` on disk).
    @discardableResult
    static func patchRootEnabledLineAfterSharpener(enabled: Bool) -> Bool {
        let path = Self.configPath
        guard FileManager.default.fileExists(atPath: path) else { return false }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty,
              var s = String(data: data, encoding: .utf8) else { return false }
        let ns = s as NSString
        let shRange = ns.range(of: "sharpener")
        guard shRange.location != NSNotFound else { return false }
        guard let re = try? NSRegularExpression(pattern: #"(?m)^(\s*)enabled\s*=\s*(true|false)\s*$"#, options: []) else { return false }
        let full = NSRange(location: 0, length: ns.length)
        for m in re.matches(in: s as String, options: [], range: full) {
            guard m.numberOfRanges >= 3, m.range.location != NSNotFound else { continue }
            guard m.range.location > shRange.location else { continue }
            let indent = ns.substring(with: m.range(at: 1))
            let newLine = "\(indent)enabled \(enabled)"
            s = ns.replacingCharacters(in: m.range, with: newLine) as String
            return writeKDLAtomically(s)
        }
        return false
    }

    func save() {
        var kdl = "sharpener {\n"
        kdl += "    enabled \(enabled)\n"
        
        kdl += "    global {\n"
        if let r = globalRadius {
            kdl += "        radius \(r)\n"
        }
        kdl += "        squircle \(globalSquircle)\n"
        kdl += "        squircle_exponent \(Self.kdlAsciiDouble(globalSquircleExponent))\n"
        kdl += "        shadows \(globalShadows)\n"
        kdl += "        borders \(globalBorders)\n"
        kdl += "        border_width \(Self.kdlAsciiDouble(globalBorderWidth))\n"
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

        _ = Self.writeKDLAtomically(kdl)
    }

    private func serializeModule(_ m: SharpenerModuleConfig, name: String, indent: String, sub: (() -> String)? = nil) -> String {
        var kdl = "\(indent)\(name) {\n"
        kdl += "\(indent)    enabled \(m.enabled)\n"
        kdl += serializeSettings(m.settings, indent: indent + "    ")
        if let s = sub?() { kdl += s }
        kdl += "\(indent)}\n\n"
        return kdl
    }

    private func serializeSettings(_ s: SharpenerSettings, indent: String) -> String {
        var kdl = ""
        if let r = s.radius  { kdl += "\(indent)radius \(r)\n" }
        if let sq = s.squircle{ kdl += "\(indent)squircle \(sq)\n" }
        if let sqe = s.squircleExponent { kdl += "\(indent)squircle_exponent \(Self.kdlAsciiDouble(sqe))\n" }
        if let sh = s.shadows { kdl += "\(indent)shadows \(sh)\n" }
        if let b = s.borders { kdl += "\(indent)borders \(b)\n" }
        if let bw = s.borderWidth { kdl += "\(indent)border_width \(Self.kdlAsciiDouble(bw))\n" }
        if let ba = s.borderColorActive { kdl += "\(indent)border_color_active \"\(ba)\"\n" }
        if let bi = s.borderColorInactive { kdl += "\(indent)border_color_inactive \"\(bi)\"\n" }
        return kdl
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
