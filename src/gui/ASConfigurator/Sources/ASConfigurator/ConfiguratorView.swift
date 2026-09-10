/**
 * Apple Sharpener: Configurator Main View
 *
 * Provides the SwiftUI-based user interface for adjusting sharpening
 * parameters, managing app rules, and toggling module states.
 */

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
                    Button(action: { 
                        if tab == .editor && t != .editor {
                            // Committing when leaving the editor tab
                            model.commitFormattedKDL()
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { tab = t } 
                    }) {
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
                Toggle("", isOn: Binding(
                    get: { model.enabled },
                    set: { newValue in
                        // If we are switching the master toggle, ensure any pending KDL edits are flushed first
                        if tab == .editor { model.commitFormattedKDL() }
                        model.enabled = newValue
                        model.save()
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
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
                    KDLEditorView(model: model)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: tab)
        }
        .frame(width: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if model.reload() {
                model.syncRuntimeMirrors()
            }
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
        }
    }
}

struct GlobalSection: View {
    @ObservedObject var model: ConfigModel
    var body: some View {
        SettingsSection(title: "Global / Common") {
            SliderRow(
                label: "Corner Radius",
                sub: "Globally affects both Dock and Windows",
                value: Binding(
                    get: { model.globalRadius ?? 14 },
                    set: { model.globalRadius = $0 }
                ),
                range: 0...100,
                format: "%d",
                disableValue: 0
            )
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
        .onChange(of: model.globalRadius) { _, _ in model.saveDebounced() }
        .onChange(of: model.globalSquircle) { _, _ in model.save() }
        .onChange(of: model.globalSquircleExponent) { _, _ in model.saveDebounced() }
        .onChange(of: model.globalShadows) { _, _ in model.save() }
        .onChange(of: model.globalBorders) { _, _ in model.save() }
        .onChange(of: model.globalBorderWidth) { _, _ in model.saveDebounced() }
        .onChange(of: model.globalBorderColorActive) { _, _ in model.saveDebounced() }
        .onChange(of: model.globalBorderColorInactive) { _, _ in model.saveDebounced() }
    }
}

struct WindowsSection: View {
    @ObservedObject var model: ConfigModel
    var body: some View {
        SettingsSection(title: "Windows Module") {
            ToggleRow(label: "Window Sharpening", value: $model.windowsEnabled)
            if model.windowsEnabled {
                Divider()
                WindowModuleCoreSettings(model: model)
                TrafficLightSettings(model: model)
                SidebarSettings(model: model)
                ToolbarSettings(model: model)
            }
        }
        .onChange(of: model.windowsEnabled) { _, _ in model.save() }
        .onChange(of: model.windowsRadius) { _, _ in model.saveDebounced() }
        .onChange(of: model.windowsSquircle) { _, _ in model.save() }
        .onChange(of: model.windowsSquircleExponent) { _, _ in model.saveDebounced() }
        .onChange(of: model.windowsShadows) { _, _ in model.save() }
        .onChange(of: model.windowsBorders) { _, _ in model.save() }
        .onChange(of: model.windowsBorderWidth) { _, _ in model.saveDebounced() }
        .onChange(of: model.windowsBorderColorActive) { _, _ in model.saveDebounced() }
        .onChange(of: model.windowsBorderColorInactive) { _, _ in model.saveDebounced() }
    }
}

struct WindowModuleCoreSettings: View {
    @ObservedObject var model: ConfigModel
    var body: some View {
        Group {
            TriStateSliderRow(label: "Window Radius", value: $model.windowsRadius, range: 0...100, format: "%d")
            Divider()
            TriStateRow(label: "Window Squircle", value: $model.windowsSquircle, inheritSource: model.globalSquircle)
            if model.windowsSquircle == true {
                Divider()
                TriStateSliderRow(label: "Squircle Exponent", value: $model.windowsSquircleExponent, range: 1.0...6.0, format: "%.1f")
            }
            Divider()
            TriStateRow(label: "Window Shadows", value: $model.windowsShadows, inheritSource: model.globalShadows)
            Divider()
            TriStateRow(label: "Window Borders", value: $model.windowsBorders, inheritSource: model.globalBorders)
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
        .onChange(of: model.trafficLightsMode) { _, _ in model.save() }
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
        .onChange(of: model.sidebarMode) { _, _ in model.save() }
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
        .onChange(of: model.toolbarMode) { _, _ in model.save() }
    }
}

struct DockSection: View {
    @ObservedObject var model: ConfigModel
    var body: some View {
        SettingsSection(title: "Dock Module") {
            ToggleRow(label: "Dock Sharpening", value: $model.dockEnabled)
            if model.dockEnabled {
                Divider()
                TriStateSliderRow(label: "Dock Radius", value: $model.dockRadius, range: 0...46, format: "%d")
                Divider()
                TriStateRow(label: "Dock Squircle", value: $model.dockSquircle, inheritSource: model.globalSquircle)
                Divider()
                TriStateRow(label: "Dock Borders", value: $model.dockBorders, inheritSource: model.globalBorders)
                if model.dockBorders == true {
                    TriStateSliderRow(label: "Border Width", value: $model.dockBorderWidth, range: 1...12, format: "%.1f")
                    Divider()
                    TriStateColorRow(label: "Active Border Color", hexString: $model.dockBorderColorActive, defaultHex: model.systemAccentColorHex)
                    Divider()
                    TriStateColorRow(label: "Inactive Border Color", hexString: $model.dockBorderColorInactive, defaultHex: "0xFF808080")
                }
            }
        }
        .onChange(of: model.dockEnabled) { _, _ in model.save() }
        .onChange(of: model.dockRadius) { _, _ in model.saveDebounced() }
        .onChange(of: model.dockSquircle) { _, _ in model.save() }
        .onChange(of: model.dockBorders) { _, _ in model.save() }
        .onChange(of: model.dockBorderWidth) { _, _ in model.saveDebounced() }
        .onChange(of: model.dockBorderColorActive) { _, _ in model.saveDebounced() }
        .onChange(of: model.dockBorderColorInactive) { _, _ in model.saveDebounced() }
    }
}

struct AppRulesSection: View {
    @ObservedObject var model: ConfigModel
    @State private var showAddAppPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PER-APP OVERRIDES (WINDOWS)").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            ForEach($model.rules) { $rule in
                AppRuleCard(model: model, rule: $rule, onDelete: {
                    if let idx = model.rules.firstIndex(where: { $0.id == rule.id }) {
                        model.rules.remove(at: idx); model.save()
                    }
                })
                .onChange(of: rule) { _, _ in model.saveDebounced() }
            }

            Button(action: { showAddAppPicker = true }) {
                Label("Add Rule", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassFallback)
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showAddAppPicker) {
            AddAppRuleSheet(model: model)
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
    let label: String
    var sub: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var disableValue: Double? = nil
    /// When true, slider snaps to integers and the label uses `format` with a rounded Int (never pass Doubles to `%d`.)
    private var integerStepping: Bool = false

    init(label: String, sub: String? = nil, value: Binding<Double>, range: ClosedRange<Double>, format: String, disableValue: Double? = nil) {
        self.label = label
        self.sub = sub
        self._value = value
        self.range = range
        self.format = format
        self.disableValue = disableValue
        self.integerStepping = false
    }
    init(label: String, sub: String? = nil, value: Binding<Int>, range: ClosedRange<Double>, format: String, disableValue: Int? = nil) {
        self.label = label
        self.sub = sub
        self.range = range
        self.format = format
        self.disableValue = disableValue.map { Double($0) }
        self.integerStepping = true
        let lo = Int(range.lowerBound.rounded())
        let hi = Int(range.upperBound.rounded())
        self._value = Binding(
            get: { Double(value.wrappedValue) },
            set: { new in
                let i = Int(new.rounded())
                value.wrappedValue = max(lo, min(hi, i))
            }
        )
    }

    private var valueLabel: String {
        if integerStepping {
            return String(format: format, Int(value.rounded()))
        }
        return String(format: format, value)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 13, weight: .medium))
                if let s = sub { Text(s).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer()
            HStack(spacing: 8) {
                Text(valueLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 34, alignment: .trailing)
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

/// Optional bool: `nil` = omit from config (inherit globally). Matches tri-slider UX: Customize → edit → reset to inherit.
struct TriStateRow: View {
    let label: String
    var sub: String? = nil
    @Binding var value: Bool?
    /// Value used when the user taps **Customize** (usually the current global setting).
    var inheritSource: Bool = true

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 13, weight: .medium))
                if let s = sub { Text(s).font(.system(size: 11)).foregroundStyle(.secondary) }
                if value == nil {
                    Text("Inheriting").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if value != nil {
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { value! },
                        set: { value = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    Button(action: { value = nil }) {
                        Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: { value = inheritSource }) {
                    Text("Customize").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
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
    let label: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let format: String
    /// Int? backing uses rounded values; label must not use `%d` with a Double.
    private var integerStepping: Bool = false

    init(label: String, value: Binding<Double?>, range: ClosedRange<Double>, format: String) {
        self.label = label
        self._value = value
        self.range = range
        self.format = format
        self.integerStepping = false
    }
    init(label: String, value: Binding<Int?>, range: ClosedRange<Double>, format: String) {
        self.label = label
        self.range = range
        self.format = format
        self.integerStepping = true
        let lo = Int(range.lowerBound.rounded())
        let hi = Int(range.upperBound.rounded())
        self._value = Binding(
            get: { value.wrappedValue.map { Double($0) } },
            set: { newValue in
                value.wrappedValue = newValue.map { raw in
                    max(lo, min(hi, Int(raw.rounded())))
                }
            }
        )
    }

    private func valueLabel(_ d: Double) -> String {
        if integerStepping {
            return String(format: format, Int(d.rounded()))
        }
        return String(format: format, d)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 13, weight: .medium))
                if value == nil { Text("Inheriting").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            Spacer()
            if value != nil {
                HStack(spacing: 8) {
                    Text(valueLabel(value!))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 34, alignment: .trailing)
                    Slider(value: Binding(get: { value! }, set: { value = $0 }), in: range).frame(width: 100)
                    Button(action: { value = nil }) { Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            } else {
                Button(action: { value = range.lowerBound + (range.upperBound - range.lowerBound) / 2 }) {
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
    @Binding var rule: AppRuleModel
    let onDelete: () -> Void
    @State private var expanded = false
    @State private var resolvedAppName = ""
    @State private var appIcon: NSImage?

    private var headline: String {
        resolvedAppName.isEmpty ? rule.bundleId : resolvedAppName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Group {
                        if let icon = appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        } else {
                            Image(systemName: "app.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(headline)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        if headline != rule.bundleId {
                            Text(rule.bundleId)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { expanded.toggle() } }

                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .onAppear { loadAppMetadata() }
            .onChange(of: rule.bundleId) { _, _ in loadAppMetadata() }
            if expanded {
                Divider()
                VStack(spacing: 0) {
                    Group {
                        Text("APP OVERRIDE STATE").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 8)
                        TriStateRow(label: "Sharpener", value: $rule.enabled, inheritSource: model.windowsEnabled)
                    }
                    
                    if rule.enabled == true {
                        Divider()
                        Group {
                            Text("MASTER WINDOW SETTINGS").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 8)
                            TriStateSliderRow(label: "Radius", value: $rule.radius, range: 0...100, format: "%d")
                            Divider()
                            TriStateRow(label: "Squircle", value: $rule.squircle, inheritSource: model.globalSquircle)
                            Divider()
                            TriStateRow(label: "Shadows", value: $rule.shadows, inheritSource: model.globalShadows)
                            Divider()
                            TriStateRow(label: "Borders", value: $rule.borders, inheritSource: model.globalBorders)
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

    private func loadAppMetadata() {
        let bid = rule.bundleId
        resolvedAppName = ""
        appIcon = nil
        DispatchQueue.global(qos: .utility).async {
            let name: String
            let icon: NSImage?
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let b = Bundle(url: url)
                name = b?.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? b?.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                icon = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                name = bid
                icon = nil
            }
            DispatchQueue.main.async {
                self.resolvedAppName = name
                self.appIcon = icon
            }
        }
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
    @ObservedObject var model: ConfigModel
    @State private var shareButtonRect: NSRect = .zero
    private let path = NSHomeDirectory() + "/.config/sharpener/config.kdl"
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                KDLTextEditor(text: $model.editorText, model: model)
                    .glassCard()
                    .padding(16)

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
            .frame(maxHeight: .infinity)

            // Path + actions: real layout height (no overlay overlap with the editor)
            VStack(alignment: .leading, spacing: 10) {
                let displayPath = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16, alignment: .center)
                        .accessibilityHidden(true)

                    Text(displayPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    Button(action: copyPath) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy path to clipboard")
                }

                Button(action: revealInFinder) {
                    Label("Reveal in Finder", systemImage: "arrow.forward.folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Show config file in Finder")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(height: 580)
        .onAppear {
            if model.editorText.isEmpty {
                model.editorText = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "# \(path) not found"
            }
        }
        .onChange(of: model.configFileGeneration) { _, _ in
            guard let disk = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            model.editorText = disk
        }
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    private func revealInFinder() {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
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

/// Text view that reliably becomes first responder so Edit menu / ⌘C routes correctly under SwiftUI hosting.
final class KDLCodeTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { scrollRangeToVisible(selectedRange()) }
        return ok
    }
}

struct KDLTextEditor: NSViewRepresentable {
    @Binding var text: String
    var model: ConfigModel
    func makeNSView(context: Context) -> NSScrollView {
        let sc = NSScrollView()
        sc.hasVerticalScroller = true
        sc.drawsBackground = false
        sc.autohidesScrollers = false
        sc.borderType = .noBorder
        let tv = KDLCodeTextView()
        tv.drawsBackground = false
        tv.isEditable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.font = NSFont(name: "SF Mono", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textColor = .labelColor
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.delegate = context.coordinator
        sc.documentView = tv
        context.coordinator.textView = tv
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
            timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in Task { @MainActor in self?.commitFormattedKDLIfValid() } }
        }
        func textView(_ tv: NSTextView, shouldChangeTextIn r: NSRange, replacementString s: String?) -> Bool {
            if s == "\n" {
                let txt = tv.string as NSString; let lr = txt.lineRange(for: NSRange(location: r.location, length: 0))
                let l = txt.substring(with: lr); let w = l.prefix(while: { $0 == " " || $0 == "\t" })
                if !w.isEmpty { tv.insertText("\n\(w)", replacementRange: r); return false }
            }
            return true
        }
        /// Parse, canonicalize in the text view, write `config.kdl`, reload model — debounced after edits.
        @MainActor func commitFormattedKDLIfValid() {
            parent.model.commitFormattedKDL()
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
