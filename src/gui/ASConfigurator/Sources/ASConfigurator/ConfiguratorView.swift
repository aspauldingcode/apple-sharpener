import SwiftUI
import AppKit
import KDL

// MARK: - Tab enum
enum ConfigTab: String, CaseIterable {
    case settings = "Settings"
    case editor   = "Config Editor"
    var icon: String { self == .settings ? "slider.horizontal.3" : "doc.text" }
}

// MARK: - Root configurator view
struct ConfiguratorView: View {
    let delegate: AppMenuDelegate
    @State private var tab: ConfigTab = .settings
    @StateObject private var model = ConfigModel()

    var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar ─────────────────────────────────────────────
            HStack(spacing: 4) {
                ForEach(ConfigTab.allCases, id: \.self) { t in
                    Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { tab = t } }) {
                        HStack(spacing: 6) {
                            Image(systemName: t.icon)
                            Text(t.rawValue)
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(GlassToolbarButtonStyle(isSelected: tab == t))
                }
                Spacer()
                Toggle("", isOn: $model.enabled).toggleStyle(.switch).labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial.opacity(0.5))

            Divider()

            // ── Content ──────────────────────────────────────────────
            Group {
                if tab == .settings {
                    SettingsTabView(model: model)
                } else {
                    KDLEditorView(model: model, delegate: delegate)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: tab)
        }
        .frame(width: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { 
            model.reload()
            model.save() // Sync KDL to UserDefaults suites on startup
        }
    }
}

// MARK: - Glass Toolbar Style
struct GlassToolbarButtonStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? .primary : .secondary)
            .background {
                if isSelected {
                    if #available(macOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 8)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.15))
                    }
                } else if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Settings Tab
struct SettingsTabView: View {
    @ObservedObject var model: ConfigModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Sharpener Configurator").font(.title3.bold())
                        Text("Master controls and module-level inheritance.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)

                if model.enabled {
                    GlobalSection(model: model)
                    WindowsSection(model: model)
                    DockSection(model: model)
                    AppRulesSection(model: model)
                } else {
                    DisabledView()
                }
            }
            .padding(20)
            .onChange(of: model.enabled) { model.save() }
        }
    }
}

struct GlobalSection: View {
    @ObservedObject var model: ConfigModel
    var body: some View {
        SettingsSection(title: "Global / Common") {
            GlobalTriStateSliderRow(label: "Corner Radius", value: $model.globalRadius, range: 0...100, format: "%d")
            Divider()
            ToggleRow(label: "Squircle Curvature", sub: "Square + circle (squircle) curvature", value: $model.globalSquircle)
            if model.globalSquircle {
                Divider()
                SliderRow(label: "Squircle Exponent", value: $model.globalSquircleExponent, range: 1.0...6.0, format: "%.1f", disableValue: 4.0)
            }
            Divider()
            ToggleRow(label: "Window Shadows", sub: "Ties well with borders", value: $model.globalShadows)
            Divider()
            ToggleRow(label: "Window Borders", value: $model.globalBorders)
            Divider()
            SliderRow(label: "Border Width", value: $model.globalBorderWidth, range: 1...12, format: "%.1f", disableValue: 4.0)
            Divider()
            ColorRow(label: "Active Border Color", hexString: $model.globalBorderColorActive)
            Divider()
            ColorRow(label: "Inactive Border Color", hexString: $model.globalBorderColorInactive)
        }
        .onChange(of: model.globalRadius) { model.save() }
        .onChange(of: model.globalSquircle) { model.save() }
        .onChange(of: model.globalSquircleExponent) { model.save() }
        .onChange(of: model.globalShadows) { model.save() }
        .onChange(of: model.globalBorders) { model.save() }
        .onChange(of: model.globalBorderWidth) { model.save() }
        .onChange(of: model.globalBorderColorActive) { model.save() }
        .onChange(of: model.globalBorderColorInactive) { model.save() }
    }
}

struct WindowsSection: View {
    @ObservedObject var model: ConfigModel
    var body: some View {
        SettingsSection(title: "Windows Module") {
            ToggleRow(label: "Enable Window Sharpening", value: $model.windowsEnabled)
            if model.windowsEnabled {
                Divider()
                WindowModuleCoreSettings(model: model)
                TrafficLightSettings(model: model)
                SidebarSettings(model: model)
                ToolbarSettings(model: model)
            }
        }
        .onChange(of: model.windowsEnabled) { model.save() }
        .onChange(of: model.windowsRadius) { model.save() }
        .onChange(of: model.windowsSquircle) { model.save() }
        .onChange(of: model.windowsSquircleExponent) { model.save() }
        .onChange(of: model.windowsShadows) { model.save() }
        .onChange(of: model.windowsBorders) { model.save() }
        .onChange(of: model.windowsBorderWidth) { model.save() }
    }
}

struct WindowModuleCoreSettings: View {
    @ObservedObject var model: ConfigModel
    var body: some View {
        Group {
            TriStateSliderRow(label: "Window Radius", value: $model.windowsRadius, range: 0...100, format: "%d")
            Divider()
            TriStateRow(label: "Window Squircle", value: $model.windowsSquircle)
            if model.windowsSquircle == true {
                Divider()
                TriStateSliderRow(label: "Squircle Exponent", value: $model.windowsSquircleExponent, range: 1.0...6.0, format: "%.1f")
            }
            Divider()
            TriStateRow(label: "Window Shadows", value: $model.windowsShadows)
            Divider()
            TriStateRow(label: "Window Borders", value: $model.windowsBorders)
            if model.windowsBorders == true {
                TriStateSliderRow(label: "Border Width", value: $model.windowsBorderWidth, range: 1...12, format: "%.1f")
                Divider()
                TriStateColorRow(label: "Active Border Color", hexString: $model.windowsBorderColorActive, defaultHex: model.systemAccentColorHex)
                Divider()
                TriStateColorRow(label: "Inactive Border Color", hexString: $model.windowsBorderColorInactive, defaultHex: "0xFF808080")
            }
        }
    }
}

struct TrafficLightSettings: View {
    @ObservedObject var model: ConfigModel
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            StringTriStateRow(label: "Traffic Lights", sub: "Square or Default macOS dots", value: $model.trafficLightsMode, showInherit: false)
                .background(Color.black.opacity(0.05))
        }
        .onChange(of: model.trafficLightsMode) { model.save() }
    }
}

struct SidebarSettings: View {
    @ObservedObject var model: ConfigModel
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            StringTriStateRow(label: "Sidebars", sub: "Apply square corners to Sidebars", value: $model.sidebarMode, showInherit: false)
                .background(Color.black.opacity(0.05))
        }
        .onChange(of: model.sidebarMode) { model.save() }
    }
}

struct ToolbarSettings: View {
    @ObservedObject var model: ConfigModel
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            StringTriStateRow(label: "Toolbars", sub: "Apply square corners to Toolbars", value: $model.toolbarMode, showInherit: false)
                .background(Color.black.opacity(0.05))
        }
        .onChange(of: model.toolbarMode) { model.save() }
    }
}

struct DockSection: View {
    @ObservedObject var model: ConfigModel
    var body: some View {
        SettingsSection(title: "Dock Module") {
            ToggleRow(label: "Enable Dock Sharpening", value: $model.dockEnabled)
            if model.dockEnabled {
                Divider()
                TriStateSliderRow(label: "Dock Radius", value: $model.dockRadius, range: 0...120, format: "%d")
                Divider()
                TriStateRow(label: "Dock Squircle", value: $model.dockSquircle)
                Divider()
                TriStateRow(label: "Dock Borders", value: $model.dockBorders)
                if model.dockBorders == true {
                    TriStateSliderRow(label: "Border Width", value: $model.dockBorderWidth, range: 1...12, format: "%.1f")
                    Divider()
                    TriStateColorRow(label: "Active Border Color", hexString: $model.dockBorderColorActive, defaultHex: model.systemAccentColorHex)
                    Divider()
                    TriStateColorRow(label: "Inactive Border Color", hexString: $model.dockBorderColorInactive, defaultHex: "0xFF808080")
                }
            }
        }
        .onChange(of: model.dockEnabled) { model.save() }
        .onChange(of: model.dockRadius) { model.save() }
        .onChange(of: model.dockSquircle) { model.save() }
    }
}

struct AppRulesSection: View {
    @ObservedObject var model: ConfigModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PER-APP OVERRIDES (WINDOWS)").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            ForEach($model.rules) { $rule in
                AppRuleCard(model: model, rule: $rule, onDelete: {
                    if let idx = model.rules.firstIndex(where: { $0.id == rule.id }) {
                        model.rules.remove(at: idx); model.save()
                    }
                })
                .onChange(of: rule) { model.save() }
            }
            
            Button(action: addRule) {
                Label("Add Rule", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassFallback)
        }
        .padding(.horizontal, 4)
    }

    private func addRule() {
        let alert = NSAlert()
        alert.messageText = "New App Rule"; alert.informativeText = "Enter Bundle ID or App Name"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = f; alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let id = f.stringValue.trimmingCharacters(in: .whitespaces)
            if !id.isEmpty { model.rules.append(AppRuleModel(bundleId: id)); model.save() }
        }
    }
}

struct DisabledView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "power.circle.fill")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Sharpener is Globally Disabled")
                .font(.headline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(60).glassCard()
    }
}

// MARK: - Helpers
extension ButtonStyle where Self == GlassFallbackButtonStyle {
    static var glassFallback: GlassFallbackButtonStyle { GlassFallbackButtonStyle() }
}
struct GlassFallbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .background {
                if #available(macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 10).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.1), lineWidth: 1))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String; @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            content().padding(.bottom, 6)
        }
        .glassCard()
    }
}

struct ToggleRow: View {
    let label: String; var sub: String? = nil; @Binding var value: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(label).font(.system(size: 13, weight: .medium))
                if let s = sub { Text(s).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer(); Toggle("", isOn: $value).toggleStyle(.switch).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

struct SliderRow: View {
    let label: String; var sub: String? = nil; @Binding var value: Double; let range: ClosedRange<Double>; let format: String; var disableValue: Double? = nil
    init(label: String, sub: String? = nil, value: Binding<Double>, range: ClosedRange<Double>, format: String, disableValue: Double? = nil) { 
        self.label = label; self.sub = sub; self._value = value; self.range = range; self.format = format; self.disableValue = disableValue 
    }
    init(label: String, sub: String? = nil, value: Binding<Int>, range: ClosedRange<Double>, format: String, disableValue: Int? = nil) {
        self.label = label; self.sub = sub; self.range = range; self.format = format; self.disableValue = disableValue.map { Double($0) }
        self._value = Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) })
    }
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 13, weight: .medium))
                if let s = sub { Text(s).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer()
            HStack(spacing: 8) {
                Text(String(format: format, value)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                Slider(value: $value, in: range).frame(width: 100)
                if let dVal = disableValue {
                    Button(action: { value = dVal }) { 
                        Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary) 
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

struct TriStateRow: View {
    let label: String; @Binding var value: Bool?
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .medium)); Spacer()
            Picker("", selection: Binding(get: { value == nil ? 0 : (value! ? 1 : 2) }, set: { v in value = v == 0 ? nil : v == 1 })) {
                Text("Inherit").tag(0); Text("On").tag(1); Text("Off").tag(2)
            }
            .pickerStyle(.segmented).frame(width: 160).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

struct StringTriStateRow: View {
    let label: String
    var sub: String? = nil
    @Binding var value: String // "inherit", "square", "default"
    var showInherit: Bool = true
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(label).font(.system(size: 13, weight: .medium))
                if let s = sub { Text(s).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer()
            Picker("", selection: $value) {
                if showInherit { Text("Inherit").tag("inherit") }
                Text("Square").tag("square")
                Text("Default").tag("default")
            }
            .pickerStyle(.segmented).frame(width: showInherit ? 180 : 120).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

struct TriStateSliderRow: View {
    let label: String; @Binding var value: Double?; let range: ClosedRange<Double>; let format: String
    init(label: String, value: Binding<Double?>, range: ClosedRange<Double>, format: String) { self.label = label; self._value = value; self.range = range; self.format = format }
    init(label: String, value: Binding<Int?>, range: ClosedRange<Double>, format: String) {
        self.label = label; self.range = range; self.format = format
        self._value = Binding(get: { value.wrappedValue.map { Double($0) } }, set: { newValue in value.wrappedValue = newValue.map { Int($0) } })
    }
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 13, weight: .medium))
                if value == nil { Text("Inheriting").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            Spacer()
            if let v = Binding($value) {
                HStack(spacing: 8) {
                    Text(String(format: format, v.wrappedValue)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                    Slider(value: v, in: range).frame(width: 100)
                    Button(action: { value = nil }) { Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            } else {
                Button(action: { value = range.lowerBound + (range.upperBound-range.lowerBound)/2 }) {
                    Text("Customize").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(.blue.opacity(0.15), in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

struct ColorRow: View {
    let label: String
    @Binding var hexString: String

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: NSColor(hexARGB: hexString) ?? .red)
            },
            set: { newColor in
                guard let nsColor = NSColor(newColor).usingColorSpace(.deviceRGB) else { return }
                let a = Int(nsColor.alphaComponent * 255)
                let r = Int(nsColor.redComponent * 255)
                let g = Int(nsColor.greenComponent * 255)
                let b = Int(nsColor.blueComponent * 255)
                hexString = String(format: "0x%02X%02X%02X%02X", a, r, g, b)
            }
        )
    }

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .medium))
            Spacer()
            ColorPicker("", selection: colorBinding).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

struct GlobalTriStateSliderRow: View {
    let label: String; @Binding var value: Double?; let range: ClosedRange<Double>; let format: String
    init(label: String, value: Binding<Double?>, range: ClosedRange<Double>, format: String) { self.label = label; self._value = value; self.range = range; self.format = format }
    init(label: String, value: Binding<Int?>, range: ClosedRange<Double>, format: String) {
        self.label = label; self.range = range; self.format = format
        self._value = Binding(get: { value.wrappedValue.map { Double($0) } }, set: { newValue in value.wrappedValue = newValue.map { Int($0) } })
    }
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 13, weight: .medium))
                if value == nil { Text("Disabled").font(.system(size: 10)).foregroundStyle(.secondary) }
                else { Text("Globally affects both Dock and Windows").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer()
            if let v = Binding($value) {
                HStack(spacing: 8) {
                    Text(String(format: format, v.wrappedValue)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                    Slider(value: v, in: range).frame(width: 100)
                    Button(action: { value = nil }) { Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            } else {
                Button(action: { value = range.lowerBound + (range.upperBound-range.lowerBound)/2 }) {
                    Text("Enable").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(.blue.opacity(0.15), in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

struct TriStateColorRow: View {
    let label: String
    @Binding var hexString: String?
    let defaultHex: String

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: NSColor(hexARGB: hexString ?? defaultHex) ?? .red)
            },
            set: { newColor in
                guard let nsColor = NSColor(newColor).usingColorSpace(.deviceRGB) else { return }
                let a = Int(nsColor.alphaComponent * 255)
                let r = Int(nsColor.redComponent * 255)
                let g = Int(nsColor.greenComponent * 255)
                let b = Int(nsColor.blueComponent * 255)
                hexString = String(format: "0x%02X%02X%02X%02X", a, r, g, b)
            }
        )
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 13, weight: .medium))
                if hexString == nil { Text("Inheriting").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            Spacer()
            if hexString != nil {
                ColorPicker("", selection: colorBinding).labelsHidden()
                Button(action: { hexString = nil }) { Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).padding(.leading, 8)
            } else {
                Button(action: { hexString = defaultHex }) {
                    Text("Customize").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(.blue.opacity(0.15), in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

extension NSColor {
    convenience init?(hexARGB: String) {
        var s = hexARGB.uppercased()
        if s.hasPrefix("0X") { s = String(s.dropFirst(2)) }
        guard s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255.0,
                  green: CGFloat((v >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(v & 0xFF) / 255.0,
                  alpha: CGFloat((v >> 24) & 0xFF) / 255.0)
    }
}

struct AppRuleCard: View {
    @ObservedObject var model: ConfigModel
    @Binding var rule: AppRuleModel; let onDelete: () -> Void; @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    Text(rule.bundleId).font(.system(size: 13, weight: .medium)); Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { expanded.toggle() } }
                
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            if expanded {
                Divider()
                VStack(spacing: 0) {
                    Group {
                        Text("APP OVERRIDE STATE").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 8)
                        TriStateRow(label: "Enable Sharpener", value: $rule.enabled)
                    }
                    
                    if rule.enabled == true {
                        Divider()
                        Group {
                            Text("MASTER WINDOW SETTINGS").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 8)
                            TriStateSliderRow(label: "Radius", value: $rule.radius, range: 0...100, format: "%d")
                            Divider()
                            TriStateRow(label: "Squircle", value: $rule.squircle)
                            Divider()
                            TriStateRow(label: "Shadows", value: $rule.shadows)
                            Divider()
                            TriStateRow(label: "Borders", value: $rule.borders)
                            if rule.borders == true {
                                TriStateSliderRow(label: "Border Width", value: $rule.borderWidth, range: 1...12, format: "%.1f")
                                Divider()
                                TriStateColorRow(label: "Active Border Color", hexString: $rule.borderColorActive, defaultHex: model.systemAccentColorHex)
                                Divider()
                                TriStateColorRow(label: "Inactive Border Color", hexString: $rule.borderColorInactive, defaultHex: "0xFF808080")
                            }
                        }
                        
                        Divider()
                        VStack(alignment: .leading, spacing: 0) {
                            StringTriStateRow(label: "TRAFFIC LIGHTS", value: $rule.trafficLights.mode)
                                .font(.system(size: 9, weight: .bold))
                        }
                        Divider()
                        AppRuleModuleOverride(title: "SQUARE SIDEBARS", override: $rule.sidebar)
                        Divider()
                        AppRuleModuleOverride(title: "SQUARE TOOLBARS", override: $rule.toolbar)
                    }
                }
                .background(Color.black.opacity(0.05))
            }
        }.glassCard()
    }
}

struct AppRuleModuleOverride: View {
    let title: String
    @Binding var override: AppRuleModel.ModuleOverride
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StringTriStateRow(label: title, value: $override.mode)
                .font(.system(size: 9, weight: .bold))
        }
    }
}

// ── Glass Card & Editor wrappers remain same but consolidated ──
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12)) }
        else { content.padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1), lineWidth: 1)) }
    }
}
extension View { func glassCard() -> some View { modifier(GlassCard()) } }

struct KDLEditorView: View {
    @ObservedObject var model: ConfigModel; let delegate: AppMenuDelegate; @State private var text = ""
    @State private var hasChanges = false
    @State private var shareButtonRect: NSRect = .zero
    private let path = NSHomeDirectory() + "/.config/sharpener/config.kdl"
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                KDLTextEditor(text: $text)
                    .glassCard()
                    .padding(16)
                    .onChange(of: text) { _, nv in hasChanges = true }
                
                // Share Sheet Button
                Button(action: shareConfig) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.glassCircle)
                .background(GeometryReader { geo in
                    Color.clear.onAppear { shareButtonRect = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, nv in shareButtonRect = nv }
                })
                .padding(.top, 28)
                .padding(.trailing, 28)
            }
            .overlay(alignment: .bottomLeading) {
                // Config Path Display - Overlayed to avoid shifting the button
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    
                    Button(action: copyPath) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Copy Path")
                }
                .padding(.leading, 24)
                .offset(y: 12) // Pull closer to the box
            }
            .padding(.bottom, 6) // Reduced from 12
            
            HStack {
                Spacer()
                
                Button(action: apply) {
                    Label("Format and Apply", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassFallback)
                .disabled(!hasChanges && !text.isEmpty)
                .opacity(hasChanges ? 1.0 : 0.6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12) // Reduced from 20
        }
        .frame(height: 580)
        .onAppear {
            text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "# \(path) not found"
            hasChanges = false
        }
    }

    private func apply() {
        if let doc = try? KDL.parseDocument(text) {
            let formatted = doc.description
            text = formatted
            save(formatted)
            hasChanges = false
        } else {
            // If it can't parse, we still save it (the helper handles it safely)
            save(text)
            hasChanges = false
        }
    }

    private func save(_ nv: String) {
        DispatchQueue.global(qos: .background).async {
            try? nv.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    private func shareConfig() {
        let fileURL = URL(fileURLWithPath: path)
        
        // Prioritize sharing the file itself
        let items: [Any] = [fileURL]
        let picker = NSSharingServicePicker(items: items)
        
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            // Coordinate conversion: global (screen) -> window -> local view
            let windowRect = window.convertFromScreen(shareButtonRect)
            let localRect = contentView.convert(windowRect, from: nil)
            
            // Anchor to the button's bottom-center or fallback to mid-view
            let targetRect = localRect.isEmpty ? 
                NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1) : 
                localRect
            
            picker.show(relativeTo: targetRect, of: contentView, preferredEdge: .minY)
        }
    }
}

// MARK: - Specialized Glass Buttons
extension ButtonStyle where Self == GlassCircleButtonStyle {
    static var glassCircle: GlassCircleButtonStyle { GlassCircleButtonStyle() }
}
struct GlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(10)
            .background {
                if #available(macOS 26.0, *) {
                    Circle().glassEffect(.regular.interactive(), in: .circle)
                } else {
                    Circle().fill(.white.opacity(0.15))
                        .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.interactiveSpring(), value: configuration.isPressed)
    }
}

struct KDLTextEditor: NSViewRepresentable {
    @Binding var text: String
    func makeNSView(context: Context) -> NSScrollView {
        let sc = NSScrollView(); sc.hasVerticalScroller = true; sc.drawsBackground = false
        let tv = NSTextView(); tv.isEditable = true; tv.isRichText = false; tv.allowsUndo = true
        tv.font = NSFont(name: "SF Mono", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textColor = .labelColor; tv.backgroundColor = .clear; tv.delegate = context.coordinator
        tv.textContainerInset = NSSize(width: 0, height: 10)
        sc.documentView = tv; context.coordinator.textView = tv
        return sc
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView, tv.string != text else { return }
        tv.string = text; context.coordinator.highlight(tv)
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        var parent: KDLTextEditor; weak var textView: NSTextView?; private var timer: Timer?
        init(_ p: KDLTextEditor) { parent = p }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string; highlight(tv)
            timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in Task { @MainActor in self?.format() } }
        }
        func textView(_ tv: NSTextView, shouldChangeTextIn r: NSRange, replacementString s: String?) -> Bool {
            if s == "\n" {
                let txt = tv.string as NSString; let lr = txt.lineRange(for: NSRange(location: r.location, length: 0))
                let l = txt.substring(with: lr); let w = l.prefix(while: { $0 == " " || $0 == "\t" })
                if !w.isEmpty { tv.insertText("\n\(w)", replacementRange: r); return false }
            }
            return true
        }
        func format() {
            guard let tv = textView, parent.text.count > 0 else { return }
            if let doc = try? KDL.parseDocument(tv.string) {
                let f = doc.description; if f != tv.string { let s = tv.selectedRange(); tv.string = f; parent.text = f; tv.setSelectedRange(s); highlight(tv) }
            }
        }
        func highlight(_ tv: NSTextView) {
            guard let st = tv.textStorage else { return }
            st.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: st.length))
            let s = st.string as NSString
            apply(s, st, #"//.*"#, c: .systemGreen.withAlphaComponent(0.8))
            apply(s, st, #"(?s)/\*.*?\*/"#, c: .systemGreen.withAlphaComponent(0.8))
            apply(s, st, #""([^"\\]|\\.)*""#, c: .systemOrange)
            apply(s, st, #"\b(true|false|null)\b"#, c: .systemPurple)
            apply(s, st, #"^\s*([a-zA-Z_][\w\-]*)"#, c: .systemBlue, cap: 1)
        }
        private func apply(_ s: NSString, _ st: NSTextStorage, _ p: String, c: NSColor, cap: Int = 0) {
            guard let re = try? NSRegularExpression(pattern: p, options: .anchorsMatchLines) else { return }
            for m in re.matches(in: s as String, range: NSRange(location: 0, length: s.length)) {
                let r = cap < m.numberOfRanges ? m.range(at: cap) : m.range
                if r.location != NSNotFound { st.addAttribute(.foregroundColor, value: c, range: r) }
            }
        }
    }
}
