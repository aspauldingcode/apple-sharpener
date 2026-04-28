# Liquid Glass in macOS Tahoe & iOS 26

## Official Apple Resources

*   **Apple Newsroom: [“New Software Design” (June 2025)](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)** – Announces the Liquid Glass material as part of the macOS Tahoe redesign. Apple describes Liquid Glass as a “translucent material” that “dynamically transforms” with content. Controls and navigation elements are “crafted out of Liquid Glass” and float above app content.
*   **WWDC 2025: [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)** – Design talk introducing Liquid Glass principles. Describes Liquid Glass as a “significant new step” unifying Apple’s design language, with dynamic “lensing” of light and fluid motion in UI. Useful for understanding design intent and where to apply the new material.
*   **WWDC 2025: [Build an AppKit App with the New Design](https://developer.apple.com/videos/play/wwdc2025/310/)** – Developer session demonstrating how to adopt macOS 15’s new design in AppKit. Shows new APIs like `NSGlassEffectView` and `NSGlassEffectContainerView`, and updates to toolbars, split views, etc.
    > [!IMPORTANT]
    > To place your content on glass, use the `NSGlassEffectView` API. Setting a `contentView` allows AppKit to apply all of the necessary visual treatments... You can customize the appearance of the glass using the `cornerRadius` and `tintColor` properties.
*   **Apple Human Interface Guidelines (macOS)** – The Materials section and related pages (HIG) cover Liquid Glass usage. See “Designing for macOS – Materials” and “Toolbars” for guidance on using the new glass material and related controls.

## New UIKit APIs in iOS 26

*   **`UIGlassEffect`** – A new `UIVisualEffect` subclass (iOS 26+) that describes the glass style (`.regular`, `.clear`). Use with `UIVisualEffectView` to render Liquid Glass material. Supports `isInteractive` for press-state visual feedback.
*   **`UIGlassEffectView`** – A dedicated view that renders Liquid Glass content, replacing the older `UIVisualEffectView` pattern for glass-specific use cases. Provides deeper, more adaptive rendering.
*   **`UIGlassEffectContainerView`** – Groups multiple glass views for compositing and morphing animations, similar to `NSGlassEffectContainerView` on macOS.
*   **SwiftUI `.glassEffect()` modifier** – Applies Liquid Glass to any SwiftUI view. Supports shapes (`.rect(cornerRadius:)`, capsule), styles (`.regular`, `.clear`), tinting (`.tint(_:)`), and interactive states (`.interactive()`).
*   **`GlassEffectContainer`** – SwiftUI container for coordinated glass effects across grouped elements, enabling merge/morph transitions.
*   **`.buttonStyle(.glass)`** – A new SwiftUI button style that renders buttons with the Liquid Glass material.

### UIKit Usage (Objective-C)

```objc
// Basic glass background
if (@available(iOS 26, *)) {
    UIGlassEffect *glass = [[UIGlassEffect alloc] init];
    UIVisualEffectView *glassView =
        [[UIVisualEffectView alloc] initWithEffect:glass];
    glassView.frame = someView.bounds;
    [someView addSubview:glassView];
    // Add content to glassView.contentView
}
```

### Glass Effect Styles

| Style       | Usage                                      |
|-------------|-------------------------------------------|
| `.regular`  | Default for most UI (nav bars, toolbars)   |
| `.clear`    | Media-rich backgrounds, minimal tinting    |
| `.identity` | Conditional disable (no glass rendering)   |

## New AppKit APIs in macOS 15 (Tahoe)

*   **`NSGlassEffectView`** – A new AppKit view (macOS 15+) that displays its `contentView` on a dynamic glass material. [Apple Developer Documentation](https://docs.rs/objc2-app-kit/latest/objc2_app_kit/struct.NSGlassEffectView.html). You create an `NSGlassEffectView`, set its `contentView` to any existing view, and AppKit applies the liquid-glass effect behind it. You can adjust `cornerRadius` and `tintColor` on the glass view to customize its appearance.
*   **`NSGlassEffectContainerView`** – A new AppKit container view that merges nearby glass views for a unified effect. [Apple Developer Documentation](https://docs.rs/objc2-app-kit/latest/objc2_app_kit/struct.NSGlassEffectContainerView.html). Wrap adjacent `NSGlassEffectViews` in an `NSGlassEffectContainerView` to ensure consistent blending (liquid effect) and better performance (one rendering pass).
*   **`NSButton.BezelStyle.glass`** – A new button bezel style (macOS 15+) that uses the liquid-glass material. In AppKit’s `NSBezelStyle` enum, the glass case is described as “A bezel style with a glass effect.” Use `myButton.bezelStyle = .glass` to give a button a floating glass background (tintable via `bezelColor`).
*   **`NSControl.BorderShape`** (New) – A property to adjust control shapes (e.g., capsule vs. rounded rectangle) so UI elements can align concentrically with liquid-glass surfaces.
*   **Scroll Edge Effect** – `NSScrollView` now provides a built-in “scroll edge” effect behind floating controls (soft fade or opaque backing) to separate them from content. The effect is automatic under titlebar and split-view accessories and adapts as elements scroll.

## Apple Developer Documentation (SDK References)

*   **[`NSGlassEffectView`](https://docs.rs/objc2-app-kit/latest/objc2_app_kit/struct.NSGlassEffectView.html)** – Supports `contentView`, `cornerRadius`, `tintColor`, style (light/dark variants).
*   **[`NSGlassEffectContainerView`](https://docs.rs/objc2-app-kit/latest/objc2_app_kit/struct.NSGlassEffectContainerView.html)** – It has a `contentView` and a spacing property for merge proximity.
*   **[`NSButton.BezelStyle.glass`](https://docs.rs/objc2-app-kit/latest/x86_64-unknown-linux-gnu/objc2_app_kit/struct.NSBezelStyle.html)** – New bezel style for liquid glass buttons.
*   **`NSControl.BorderShape`** – New enum property (e.g., `.capsule`, `.roundedRect`, etc.) to control the rounding of controls.
*   **New Control Sizes & Prominence** – AppKit properties like `prefersCompactControlSizeMetrics` and `tintProminence` were introduced in macOS 15.

## Sample Code & Demos

*   **Apple Sample Projects (macOS)** – Apple’s sample code library includes Tahoe examples (search “Liquid Glass” or “TabBar”, etc.).
*   **Open-Source Demos:**
    *   **[Meridius-Labs/electron-liquid-glass](https://github.com/Meridius-Labs/electron-liquid-glass)** – An Electron framework plugin that demonstrates using `NSGlassEffectView` in a desktop app. It creates true Liquid Glass on macOS 15+, falling back to `NSVisualEffectView` on older versions.
    *   **hkandala/tauri-plugin-liquid-glass** – A Tauri (Rust) plugin providing Liquid Glass support on macOS 15+.
    *   **fsalinas26/qt-liquid-glass** – A Qt6 example project that injects the new glass effect using the Objective-C runtime for Qt apps on macOS 15.
    *   **lucasromerodb/liquid-glass-effect-macos** – A demo project recreating Liquid Glass visuals (using HTML/CSS/SVG) inspired by Apple’s design.
    *   **carolhsiaoo/awesome-liquid-glass** – A community-curated list of resources for Liquid Glass.

