/**
 * Apple Sharpener: Window Sharpening Implementation
 *
 * This file contains the core logic for modifying NSWindow corner radii,
 * applying squircle masking to layers, and managing custom window borders.
 * It uses ZKSwizzle for method swizzling in AppKit classes.
 */

#import "window.h"
#import "ZKSwizzle.h"
#import "proc_utils.h"
#import "sharpener_log.h"
#import "window_chrome_roles.h"
#import "window_filter.h"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <objc/runtime.h>

@interface CALayer (AppleSharpener_Private)
- (BOOL)_shouldBeSquare;
@end

/**
 * Window sharpening implementation for apple-sharpener
 * Applies square corners by setting window's private cornerRadius property to 0
 * via KVC
 */

#ifndef AppleSharpener
static NSString *const AppleSharpener = @"AppleSharpener";
#endif

/// Radius sent to CoreAnimation when the user requests radius = 0 (sharp corners).
/// Must be strictly positive: CA / GPU may flush a true 0 to "no rounding" without
/// honouring our layer mask, causing border-sync glitches.
/// Value 1e-7 pt (~100 nm) is visually identical to a sharp corner at any screen
/// density and is a fully normalised IEEE-754 double — unlike DBL_TRUE_MIN /
/// nextafter(0,1), which are subnormal and can be flushed to 0 by the GPU.
static const CGFloat kSharpenerNearZeroRadius = 1e-7;

#pragma mark - Global State

static BOOL disableWindowCornerRadius = YES;
static NSInteger windowCustomRadius = 0;
static BOOL squircleEnabled = YES;
static double squircleExponent = 4.0;
static BOOL globalShadows = YES;
static NSArray *appRules = nil;

// — Window Borders —
static BOOL windowBordersEnabled = NO;
static CGFloat windowBorderWidth = 4.0;
static NSString *windowBorderColorActive = nil;
static NSString *windowBorderColorInactive = nil;

// — Traffic Lights —
static NSString *trafficLightsMode = nil;

// — Sidebar —
static NSString *sidebarMode = nil;

// — Toolbar —
static NSString *toolbarMode = nil;
static BOOL isWorkspaceSwitching = NO;

static BOOL windowLoggingSetup = NO;
static id<NSObject> windowLoggingObserver = nil;
static id<NSObject> appFinishLaunchingObserver = nil;

#pragma mark - Hierarchical Settings Resolution

typedef struct {
  BOOL enabled;
  NSInteger radius;
  BOOL squircle;
  double squircleExponent;
  BOOL shadows;
  BOOL bordersEnabled;
  double borderWidth;
  NSString *__unsafe_unretained borderColorActive;
  NSString *__unsafe_unretained borderColorInactive;
  NSString *__unsafe_unretained trafficLights;
  NSString *__unsafe_unretained sidebar;
  NSString *__unsafe_unretained toolbar;
} SharpenerWindowSettings;

static SharpenerWindowSettings getSettingsForWindow(__unused NSWindow *window) {
  SharpenerWindowSettings s;
  s.enabled = disableWindowCornerRadius;
  s.radius = windowCustomRadius;
  s.squircle = squircleEnabled;
  s.squircleExponent = squircleExponent;
  s.shadows = globalShadows;
  s.bordersEnabled = windowBordersEnabled;
  s.borderWidth = windowBorderWidth;
  s.borderColorActive = windowBorderColorActive;
  s.borderColorInactive = windowBorderColorInactive;
  s.trafficLights = trafficLightsMode;
  s.sidebar = sidebarMode;
  s.toolbar = toolbarMode;

  if (!appRules)
    return s;

  NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
  if (!bundleId)
    return s;

  for (NSDictionary *rule in appRules) {
    if ([rule[@"bundleId"] isEqualToString:bundleId]) {
      if (rule[@"enabled"])
        s.enabled = [rule[@"enabled"] boolValue];
      if (rule[@"radius"])
        s.radius = [rule[@"radius"] integerValue];
      if (rule[@"squircle"])
        s.squircle = [rule[@"squircle"] boolValue];
      if (rule[@"squircleExponent"])
        s.squircleExponent = [rule[@"squircleExponent"] doubleValue];
      if (rule[@"shadows"])
        s.shadows = [rule[@"shadows"] boolValue];

      if (rule[@"borders"] != nil)
        s.bordersEnabled = [rule[@"borders"] boolValue];
      if (rule[@"borderWidth"] != nil)
        s.borderWidth = [rule[@"borderWidth"] doubleValue];
      if (rule[@"borderColorActive"] != nil)
        s.borderColorActive = rule[@"borderColorActive"];
      if (rule[@"borderColorInactive"] != nil)
        s.borderColorInactive = rule[@"borderColorInactive"];

      if (rule[@"traffic_lights"] != nil)
        s.trafficLights = rule[@"traffic_lights"];
      if (rule[@"sidebar"] != nil)
        s.sidebar = rule[@"sidebar"];
      if (rule[@"toolbar"] != nil)
        s.toolbar = rule[@"toolbar"];

      break;
    }
  }
  return s;
}

#pragma mark - Recursion & Swizzle Safety

// Recursion guard to prevent infinite loops
static const void *kApplyingSquareCornersKey = &kApplyingSquareCornersKey;

static BOOL isApplyingSquareCorners(NSWindow *window) {
  return
      [objc_getAssociatedObject(window, kApplyingSquareCornersKey) boolValue];
}

static void setApplyingSquareCorners(NSWindow *window, BOOL applying) {
  objc_setAssociatedObject(window, kApplyingSquareCornersKey, @(applying),
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// ─────────────────────────────────────────────────────────
// MARK: - Color parsing helper
// ─────────────────────────────────────────────────────────
static NSColor *colorFromHexARGB(NSString *hex) {
  if (!hex)
    return nil;
  NSString *s = [hex uppercaseString];
  if ([s hasPrefix:@"0X"])
    s = [s substringFromIndex:2];
  if (s.length != 8)
    return nil;
  unsigned int v = 0;
  [[NSScanner scannerWithString:s] scanHexInt:&v];
  return [NSColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                         green:((v >> 8) & 0xFF) / 255.0
                          blue:(v & 0xFF) / 255.0
                         alpha:((v >> 24) & 0xFF) / 255.0];
}

// ─────────────────────────────────────────────────────────
// MARK: - External Window Border (ASBorderWindow)
// ─────────────────────────────────────────────────────────

@interface ASBorderWindow : NSWindow
@property(nonatomic, assign) NSWindow *targetWindow;
@end

@implementation ASBorderWindow
- (instancetype)initWithContentRect:(NSRect)contentRect
                       targetWindow:(NSWindow *)targetWindow {
  if ((self = [super initWithContentRect:contentRect
                               styleMask:NSWindowStyleMaskBorderless
                                 backing:NSBackingStoreBuffered
                                   defer:NO])) {
    _targetWindow = targetWindow;
    self.backgroundColor = [NSColor clearColor];
    self.opaque = NO;
    self.hasShadow = NO;
    self.ignoresMouseEvents = YES;
    self.collectionBehavior = NSWindowCollectionBehaviorIgnoresCycle |
                              NSWindowCollectionBehaviorStationary |
                              NSWindowCollectionBehaviorCanJoinAllSpaces;
    self.level = targetWindow.level;

    NSView *cv =
        [[NSView alloc] initWithFrame:NSMakeRect(0, 0, contentRect.size.width,
                                                 contentRect.size.height)];
    cv.wantsLayer = YES;
    self.contentView = cv;

    CALayer *borderLayer = [CALayer layer];
    borderLayer.name = @"ASBorderLayer";
    borderLayer.backgroundColor = [NSColor clearColor].CGColor;
    borderLayer.zPosition = 9999;
    borderLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    [cv.layer addSublayer:borderLayer];
  }
  return self;
}

- (BOOL)canBecomeKeyWindow {
  return NO;
}
- (BOOL)canBecomeMainWindow {
  return NO;
}
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen {
  return frameRect;
}
@end

static NSMapTable<NSWindow *, ASBorderWindow *> *windowToBorderMap = nil;

static void initializeBorderTracking(void) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    windowToBorderMap =
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                              valueOptions:NSPointerFunctionsStrongMemory];
  });
}

/// Inset applied after expanding by border width so the stroke sits slightly
/// inside the window’s composited edge (avoids a ~1px seam).
static const CGFloat kASBorderFrameEdgePullIn = 1.0;

static NSRect calculateBorderFrame(NSRect windowFrame, CGFloat width) {
  NSRect expanded = NSInsetRect(windowFrame, -width, -width);
  return NSInsetRect(expanded, kASBorderFrameEdgePullIn, kASBorderFrameEdgePullIn);
}

static CGFloat calculateDisplayRadius(NSWindow *window,
                                      SharpenerWindowSettings s) {
  NSView *rootView = window.contentView.superview ?: window.contentView;
  if (!rootView)
    return kSharpenerNearZeroRadius;

  CGFloat effectiveRadius = (CGFloat)s.radius;
  if (effectiveRadius <= 0)
    return kSharpenerNearZeroRadius;

  CGFloat displayRadius = effectiveRadius;
  if (s.squircle) {
    displayRadius = effectiveRadius * (s.squircleExponent / 2.0);
  }

  // Clamp to half the smallest window dimension to prevent "folding" and rim
  // desync
  CGFloat maxRadius =
      MIN(rootView.bounds.size.width / 2.0, rootView.bounds.size.height / 2.0);
  displayRadius = MIN(displayRadius, maxRadius);

  if (displayRadius <= 0)
    displayRadius = kSharpenerNearZeroRadius;

  return displayRadius;
}

static void applyBorderOverlay(NSWindow *window, BOOL focused) {
  initializeBorderTracking();

  SharpenerWindowSettings s = getSettingsForWindow(window);

  if (!s.enabled || !s.bordersEnabled || !isStandardAppWindow(window) ||
      isWindowFullscreen(window) || isWorkspaceSwitching) {
    ASBorderWindow *existing = [windowToBorderMap objectForKey:window];
    if (existing) {
      [existing orderOut:nil];
      if (existing.parentWindow == window) {
        [window removeChildWindow:existing];
      }
      [windowToBorderMap removeObjectForKey:window];
    }
    return;
  }

  ASBorderWindow *borderWin = [windowToBorderMap objectForKey:window];
  NSRect targetFrame = calculateBorderFrame(window.frame, s.borderWidth);

  if (!borderWin) {
    borderWin = [[ASBorderWindow alloc] initWithContentRect:targetFrame
                                               targetWindow:window];
    [windowToBorderMap setObject:borderWin forKey:window];
  }

  // Always update the frame and level to ensure width changes are reflected
  // instantly
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  [borderWin setFrame:targetFrame display:YES];
  borderWin.level = window.level;
  [CATransaction commit];

  if (borderWin.windowNumber <= 0 || !borderWin.isVisible) {
    if (borderWin.parentWindow != window) {
      [window addChildWindow:borderWin ordered:NSWindowBelow];
    }
  }

  // Update layer properties
  CALayer *rootLayer = borderWin.contentView.layer;
  CALayer *borderLayer = nil;
  for (CALayer *l in rootLayer.sublayers) {
    if ([l.name isEqualToString:@"ASBorderLayer"]) {
      borderLayer = l;
      break;
    }
  }

  if (borderLayer) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    borderLayer.frame = rootLayer.bounds;
    borderLayer.borderWidth = s.borderWidth;
    NSColor *col = focused ? colorFromHexARGB(s.borderColorActive)
                           : colorFromHexARGB(s.borderColorInactive);
    borderLayer.borderColor = (col ?: NSColor.redColor).CGColor;

    CGFloat displayRadius = calculateDisplayRadius(window, s);

    // Synchronize border curvature with window curvature
    // If radius is 0, we want a sharp corner (displayRadius = kSharpenerNearZeroRadius)
    // If radius > 0, we want outer radius = inner radius + border width
    if (s.radius == 0) {
      borderLayer.cornerRadius = displayRadius;
    } else {
      borderLayer.cornerRadius = displayRadius + s.borderWidth;
    }

    if ([borderLayer respondsToSelector:@selector(setCornerCurve:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
      borderLayer.cornerCurve = (s.radius > 0 && s.squircle)
                                    ? kCACornerCurveContinuous
                                    : kCACornerCurveCircular;
#pragma clang diagnostic pop
    }

    [CATransaction commit];
    [borderWin display];
  }
}

// Swizzling logic for UI elements is handled via ZKSwizzle interfaces below.

#pragma mark - Helper Functions

// Recursive view walker to hide window decorations (Oowm style)
static void hideDecorationViews(NSView *view) {
  if (!view)
    return;

  @autoreleasepool {
    NSString *className = NSStringFromClass([view class]);
    if ([className containsString:@"Decoration"]) {
      view.hidden = YES;
      view.alphaValue = 0.0;
      if (view.layer) {
        view.layer.opacity = 0.0;
        view.layer.mask = nil;
      }
    }

    for (NSView *subview in view.subviews) {
      hideDecorationViews(subview);
    }
  }
}

// Recursive view walker to restore hidden window decorations
static void unhideDecorationViews(NSView *view) {
  if (!view)
    return;

  @autoreleasepool {
    NSString *className = NSStringFromClass([view class]);
    if ([className containsString:@"Decoration"]) {
      view.hidden = NO;
      view.alphaValue = 1.0;
      if (view.layer) {
        view.layer.opacity = 1.0;
      }
    }

    for (NSView *subview in view.subviews) {
      unhideDecorationViews(subview);
    }
  }
}

// ─────────────────────────────────────────────────────────
// MARK: - Specific UI Element Sharpening
// ─────────────────────────────────────────────────────────

static BOOL sharpener_square_toolbar_policy(NSView *view) {
  SharpenerWindowSettings s = getSettingsForWindow(view.window);
  return [s.toolbar isEqualToString:@"square"];
}

static BOOL sharpener_square_liquid_container(NSView *view) {
  SharpenerWindowSettings s = getSettingsForWindow(view.window);
  if (SharpenerViewChainHasTitlebarOrToolbar(view))
    return [s.toolbar isEqualToString:@"square"];
  return [s.sidebar isEqualToString:@"square"];
}

static BOOL sharpener_square_ns_glass_effect(NSGlassEffectView *view) {
  SharpenerWindowSettings s = getSettingsForWindow(view.window);
  if (SharpenerViewChainHasTitlebarOrToolbar((NSView *)view))
    return [s.toolbar isEqualToString:@"square"];
  SharpenerChromeFlags f;
  SharpenerChromeFlagsReset(&f);
  SharpenerMergeChromeFlagsFromViewChain((NSView *)view, &f);
  if (f.sidebar ||
      [(NSVisualEffectView *)view material] == NSVisualEffectMaterialSidebar)
    return [s.sidebar isEqualToString:@"square"];
  return NO;
}

// Helper function to recursively sharpen views
static void sharpenView(NSView *view, SharpenerWindowSettings s) {
  if (!view)
    return;

  NSString *className = NSStringFromClass([view class]);
  SharpenerChromeFlags chrome;
  SharpenerChromeFlagsReset(&chrome);
  SharpenerMergeChromeFlagsFromViewChain(view, &chrome);

  BOOL foundTarget = NO;

  // 1. Traffic Lights (_NSThemeCloseWidget, _NSThemeZoomWidget, _NSThemeWidget)
  if ([className containsString:@"ThemeCloseWidget"] ||
      [className containsString:@"ThemeZoomWidget"] ||
      [className containsString:@"ThemeWidget"] ||
      [className containsString:@"ThemeWidgetCell"] ||
      [className containsString:@"TrafficLight"]) {
    foundTarget = YES;
    if ([s.trafficLights isEqualToString:@"square"]) {
      if (!view.wantsLayer)
        view.wantsLayer = YES;
    } else {
      // Restore default appearance by forcing a redraw without our custom logic
      // enabled. We don't necessarily turn off wantsLayer here as it could be
      // used for other things.
    }

    // Explicitly update traffic light states to enforce layer redrawing
    if ([view respondsToSelector:@selector(updateLayer)]) {
      @try {
        [view performSelector:@selector(updateLayer)];
      } @catch (NSException *e) {
      }
    }

    // Deep invalidation
    if ([view respondsToSelector:@selector(_windowChangedKeyState)]) {
      @try {
        [view performSelector:@selector(_windowChangedKeyState)];
      } @catch (NSException *e) {
      }
    }

    [view setNeedsLayout:YES];
    [view setNeedsDisplay:YES];
    if (view.layer) {
      [view.layer setNeedsLayout];
      [view.layer setNeedsDisplay];
    }
  }

  // 2. Sidebar
  BOOL isSidebarEffect = NO;
  if ([view isKindOfClass:[NSVisualEffectView class]]) {
    if ([(NSVisualEffectView *)view material] ==
        NSVisualEffectMaterialSidebar) {
      isSidebarEffect = YES;
    }
  }

  if ([className containsString:@"_NSFullHeightSideBar"] ||
      [className containsString:@"NSSidebarView"] ||
      [className containsString:@"NSContainerConcentricGlassEffectView"] ||
      [className containsString:@"NSBlurryAlleywayView"] ||
      [className containsString:@"NSScrollPocket"] ||
      [className containsString:@"TSidebarScrollView"] || isSidebarEffect ||
      chrome.sidebar) {
    foundTarget = YES;
    if ([s.sidebar isEqualToString:@"square"]) {
      if (!view.wantsLayer)
        view.wantsLayer = YES;
    }
  }

  // 3. Toolbar
  if ([className containsString:@"ToolbarButton"] ||
      [className containsString:@"NSToolbarItemViewer"] ||
      [className containsString:@"NSToolbarView"] ||
      [className containsString:@"_NSToolbar"] ||
      [className containsString:@"NSTitlebarBackgroundView"] ||
      [className containsString:@"NSTitlebarContainerView"]) {
    foundTarget = YES;
    if ([s.toolbar isEqualToString:@"square"]) {
      if (!view.wantsLayer)
        view.wantsLayer = YES;
    }
  }

  if (foundTarget) {
    view.needsLayout = YES;
    view.needsDisplay = YES;
    if (view.layer) {
      [view.layer setNeedsLayout];
      [view.layer setNeedsDisplay];
    }
  }

  // Process all subviews
  for (NSView *subview in view.subviews) {
    sharpenView(subview, s);
  }
}

static void applySpecificUIElementSharpening(NSWindow *window) {
  // GUARD: Chromium-based apps handle their own widget rendering and internal
  // layers. Modifying them via recursive walker is unsafe and causes compositor
  // crashes.
  if (sharpener_is_chromium_based_process())
    return;

  if (!window)
    return;

  SharpenerWindowSettings s = getSettingsForWindow(window);

  // For non-fullscreen windows, require sharpener to be enabled.
  // For fullscreen windows, still run the sidebar pass when sidebar=square so
  // the sidebar that peeks into the titlebar/toolbar area gets squared.
  BOOL isFullscreen = isWindowFullscreen(window);
  if (isFullscreen) {
    if (![sidebarMode isEqualToString:@"square"])
      return;
  } else {
    if (!s.enabled)
      return;
  }

  NSView *root = window.contentView.superview ?: window.contentView;
  if (root) {
    sharpenView(root, s);
  }
}

// Apply square or squircle corners to a window - THE KEY MECHANISM
// Sets the window's private cornerRadius property to 0 via KVC
// Also applies true continuous 'squircle' masking to the underlying view layer
static void applySquareCorners(NSWindow *window) {
  SharpenerWindowSettings s = getSettingsForWindow(window);

  if (!window || !s.enabled)
    return;
  // Don't apply full sharpening to fullscreen/non-standard windows, but
  // DO run the sidebar pass — the sidebar glass peeks into the titlebar area
  // in fullscreen and needs its corner radius zeroed independently.
  if (!isStandardAppWindow(window)) {
    if ([sidebarMode isEqualToString:@"square"] && isWindowFullscreen(window)) {
      applySpecificUIElementSharpening(window);
    }
    return;
  }

  // Check recursion guard and basic window validity
  if (isApplyingSquareCorners(window))
    return;

  setApplyingSquareCorners(window, YES);

  @try {
    NSView *rootView = window.contentView.superview ?: window.contentView;
    if (rootView) {
      CGFloat displayRadius = calculateDisplayRadius(window, s);

      // Memory Guard: Chromium-based processes crash if we touch their root
      // layers too much. We ONLY apply the cornerRadius to the window itself
      // via KVC. The window server will handle the rim and shadow sharpening,
      // which is what the user actually sees.
      if (sharpener_is_chromium_based_process()) {
        // Set the corner radius on the window itself — this affects the window's
        // rim and shadow casting in the window server without touching the
        // application's internal layer tree.
        [(id)window setValue:@(displayRadius) forKey:@"cornerRadius"];
        // NOTE: We do NOT call invalidateShadow or displayIfNeeded here for
        // Chromium as it interferes with their compositor and causes rendering
        // freezes.
        return;
      }

      if (!rootView.wantsLayer) {
        rootView.wantsLayer = YES;
      }

      // Hide decoration views for crisp square corners (Oowm behavior)
      if (s.radius == 0) {
        hideDecorationViews(rootView);
      }

      // --- BOUND TOGETHER ---
      // We set the SAME displayRadius on:
      //   1. rootView.layer.cornerRadius + masksToBounds → clips content
      //   2. window KVC cornerRadius → controls rim + shadow
      //   3. (internal) border radius → synchronized in applyBorderOverlay
      // AND we return nil from _cornerMask to prevent the system from applying
      // its own internal mask (which clamps differently at high radii, causing
      // desync).

      // Epsilon trick: if displayRadius is 0, use epsilon and set opaque
      if (s.radius == 0) {
        @try {
          if ([window respondsToSelector:@selector(setOpaque:)]) {
            [window setOpaque:YES];
          }
        } @catch (NSException *e) {
        }
      }

      // --- APPLY SHARPENING ---
      rootView.layer.cornerRadius = displayRadius;
      rootView.layer.masksToBounds = YES;
      if ([rootView.layer respondsToSelector:@selector(setCornerCurve:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
        rootView.layer.cornerCurve = (s.radius > 0 && s.squircle)
                                         ? kCACornerCurveContinuous
                                         : kCACornerCurveCircular;
#pragma clang diagnostic pop
      }

      @try {
        [(id)window setValue:@(displayRadius) forKey:@"cornerRadius"];
        if ([window respondsToSelector:@selector(setHasShadow:)]) {
          if (window.hasShadow != s.shadows)
            window.hasShadow = s.shadows;
        }
        if ([window respondsToSelector:@selector(invalidateShadow)]) {
          [window invalidateShadow];
        }
      } @catch (NSException *e) {
      }

      // 5. Border overlay — color based on key-window status
      applyBorderOverlay(window, [window isKeyWindow]);

      // 6. Apply specific UI element sharpening (Traffic Lights, etc)
      applySpecificUIElementSharpening(window);

      [window displayIfNeeded];
    }
  } @catch (NSException *exception) {
    // Fail silently
  } @finally {
    setApplyingSquareCorners(window, NO);
  }
}

// Restore default macOS corners on a window (undo Apple Sharpener
// modifications)
static void restoreDefaultCorners(NSWindow *window) {
  if (!window)
    return;

  @try {
    NSView *rootView = window.contentView.superview ?: window.contentView;
    if (rootView) {
      // Remove our custom corner radius / mask — let macOS take over
      rootView.layer.cornerRadius = 0;
      rootView.layer.masksToBounds = NO;
      if (rootView.layer.mask &&
          [rootView.layer.mask.name
              isEqualToString:@"AppleSharpenerSquircleMask"]) {
        rootView.layer.mask = nil;
      }

      // Unhide any decoration views we hid
      unhideDecorationViews(rootView);
    }

    // Let the system reset its own corner radius
    @try {
      [(id)window setValue:nil forKey:@"cornerRadius"];
    } @catch (NSException *e) {
    }

    if ([window respondsToSelector:@selector(invalidateShadow)]) {
      [window invalidateShadow];
    }
    [window displayIfNeeded];
  } @catch (NSException *e) {
  }
}

#pragma mark - Public API

static id ASGetPref(NSString *suffix) {
  if (!suffix) return nil;
  NSString *key = [NSString stringWithFormat:@"AppleSharpener_%@", suffix];
  
  // 1. Check Global Domain (prefixed) - Best for Sandboxed apps
  id v = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kCFPreferencesAnyApplication);
  if (v && v != (id)[NSNull null]) return v;
  
  // 2. Check Suite Domain (prefixed)
  v = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.aspauldingcode.apple_sharpener"));
  if (v && v != (id)[NSNull null]) return v;

  // 3. Check Suite Domain (unprefixed) - Direct CLI writes
  v = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)suffix, CFSTR("com.aspauldingcode.apple_sharpener"));
  if (v && v != (id)[NSNull null]) return v;

  return nil;
}

static id ASResolve(NSString *mod, NSString *glob) {
  id val = ASGetPref(mod);
  if (val) return val;
  return ASGetPref(glob);
}

static void refreshSettings(void) {
  id gEn = ASGetPref(@"enabled");
  BOOL masterEnabled = (gEn == nil) || [gEn boolValue];

  id wEn = ASGetPref(@"windows_enabled");
  if (wEn != nil) {
    disableWindowCornerRadius = masterEnabled && [wEn boolValue];
  } else {
    disableWindowCornerRadius = masterEnabled;
  }
  
  NSLog(@"[AppleSharpener] refreshSettings: master=%d, windows=%d", masterEnabled, disableWindowCornerRadius);

  // Windows module off: same idea as dock — do not inherit global radius /
  // squircle / borders into statics (looked like `-w off` still sharpened).
  if (!disableWindowCornerRadius) {
    id val;
    id wr = ASGetPref(@"windows_radius");
    windowCustomRadius = wr ? [wr integerValue] : 0;
    if ((val = ASGetPref(@"windows_squircle")))
      squircleEnabled = [val boolValue];
    else
      squircleEnabled = YES;
    if ((val = ASGetPref(@"windows_squircle_exponent")))
      squircleExponent = [val doubleValue];
    else
      squircleExponent = 4.0;
    if ((val = ASGetPref(@"windows_shadows")))
      globalShadows = [val boolValue];
    else
      globalShadows = YES;

    windowBordersEnabled = NO;
    windowBorderWidth = 4.0;
    windowBorderColorActive = nil;
    windowBorderColorInactive = nil;

    if ((val = ASGetPref(@"traffic_lights_mode")))
      trafficLightsMode = val;
    else
      trafficLightsMode = @"default";
    if ((val = ASGetPref(@"sidebar_mode")))
      sidebarMode = val;
    else
      sidebarMode = @"default";
    if ((val = ASGetPref(@"toolbar_mode")))
      toolbarMode = val;
    else
      toolbarMode = @"default";

    if ((val = ASGetPref(@"rules")))
      appRules = (NSArray *)val;
    return;
  }

  id val;
  if ((val = ASResolve(@"windows_radius", @"radius")))
    windowCustomRadius = [val integerValue];
  else
    windowCustomRadius = 0;
  if ((val = ASResolve(@"windows_squircle", @"squircle_enabled")))
    squircleEnabled = [val boolValue];
  else
    squircleEnabled = YES;
  if ((val = ASResolve(@"windows_squircle_exponent", @"squircle_exponent")))
    squircleExponent = [val doubleValue];
  else
    squircleExponent = 4.0;
  if ((val = ASResolve(@"windows_shadows", @"global_shadows")))
    globalShadows = [val boolValue];
  else
    globalShadows = YES;

  if ((val = ASResolve(@"windows_borders", @"global_borders")))
    windowBordersEnabled = [val boolValue];
  else
    windowBordersEnabled = NO;

  if ((val = ASResolve(@"windows_border_width", @"global_border_width")))
    windowBorderWidth = [val doubleValue];
  else
    windowBorderWidth = 4.0;
  if ((val = ASResolve(@"windows_border_color_active",
                     @"global_border_color_active")))
    windowBorderColorActive = val;
  if ((val = ASResolve(@"windows_border_color_inactive",
                     @"global_border_color_inactive")))
    windowBorderColorInactive = val;

  if ((val = ASResolve(@"traffic_lights_mode", nil)))
    trafficLightsMode = val;
  else
    trafficLightsMode = @"default";

  if ((val = ASResolve(@"sidebar_mode", nil)))
    sidebarMode = val;
  else
    sidebarMode = @"default";

  if ((val = ASResolve(@"toolbar_mode", nil)))
    toolbarMode = val;
  else
    toolbarMode = @"default";

  if ((val = ASGetPref(@"rules")))
    appRules = (NSArray *)val;
}

void toggleSquareCorners(__unused BOOL enable, __unused NSInteger radius,
                         __unused BOOL squircle, __unused double exponent) {
  // Apply immediately to open windows (Corners AND Borders)
  dispatch_async(dispatch_get_main_queue(), ^{
    @try {
      NSApplication *app = [NSApplication sharedApplication];
      if (app) {
        for (NSWindow *window in app.windows) {
          BOOL isStandard = isStandardAppWindow(window);
          // Also process fullscreen windows when sidebar=square so the sidebar
          // visible in the fullscreen titlebar area gets sharpened.
          BOOL isFullscreenSidebar = isWindowFullscreen(window) &&
                                     [sidebarMode isEqualToString:@"square"];

          if (isStandard) {
            // Temporarily lift recursion guard to force a manual redraw
            setApplyingSquareCorners(window, NO);
            SharpenerWindowSettings s = getSettingsForWindow(window);
            if (!s.enabled) {
              // Module off: actually undo our layers/KVC (applySquareCorners
              // no-ops when !s.enabled).
              restoreDefaultCorners(window);
              applyBorderOverlay(window, window.isKeyWindow);
            } else {
              // Re-enable / refresh: restore first so persisted radius,
              // squircle, and borders re-apply cleanly after a module-off
              // period (menubar quick toggle, CLI, etc.).
              restoreDefaultCorners(window);
              applySquareCorners(window);
              applyBorderOverlay(window, window.isKeyWindow);
              applySpecificUIElementSharpening(window);

              // Nudge trick: modify the window frame by a tiny, invisible amount
              // to forcefully trigger a deep AppKit relayout and invalidation
              // pass inside Core Animation cache. This forces square styles to
              // hit the sublayers instantly.
              NSRect frame = window.frame;
              NSRect nudgedFrame = frame;
              nudgedFrame.size.height += 0.0001;
              nudgedFrame.size.width += 0.0001;
              [window setFrame:nudgedFrame display:NO];
              [window setFrame:frame display:YES];
              [window display];
              [window setViewsNeedDisplay:YES];
            }
          } else if (isFullscreenSidebar) {
            // For fullscreen windows: only run the sidebar-specific sharpening
            // pass. Do NOT apply applySquareCorners (that would interfere with
            // the fullscreen window frame).
            applySpecificUIElementSharpening(window);
            [window displayIfNeeded];
          }
        }
      }
    } @catch (NSException *e) {
    }
  });
}

#pragma mark - Notification Setup

static void setupWindowLogging(void) {
  @try {
    if (windowLoggingSetup)
      return;

    if (windowLoggingObserver) {
      [[NSNotificationCenter defaultCenter]
          removeObserver:windowLoggingObserver];
      windowLoggingObserver = nil;
    }

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (!center)
      return;

    windowLoggingObserver = [center
        addObserverForName:NSWindowDidBecomeKeyNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                  @try {
                    NSWindow *window = note.object;
                    if (!window || ![window isKindOfClass:[NSWindow class]])
                      return;

                    if (isStandardAppWindow(window)) {
#ifdef APPLE_SHARPENER_LOGS
                      @try {
                        NSString *title = window.title.length > 0
                                              ? window.title
                                              : @"(no title)";
                        NSString *className = NSStringFromClass([window class]);
                        SHARPENER_LOG(@"Window: %@ (%@)", title, className);
                      } @catch (NSException *e) {
                      }
#endif
                    }
                  } @catch (NSException *e) {
                  }
                }];

    windowLoggingSetup = YES;
  } @catch (NSException *e) {
  }
}

void initWindowSharpener(void) {
  @try {
    if (!NSClassFromString(@"NSApplication"))
      return;
    if (!NSClassFromString(@"NSWindow"))
      return;

    if (sharpener_is_extension_process())
      return;

    // GUARD: Chromium and Electron helper processes (Renderer, GPU, Crashpad)
    // are highly sensitive and will SIGTRAP if we even install swizzles.
    // We bail out immediately for these subprocesses.
    if (sharpener_is_chromium_helper_process())
      return;

    SHARPENER_LOG(@"initWindowSharpener running in: %@",
                  [[NSBundle mainBundle] bundleIdentifier]);

    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleId isEqualToString:@"com.apple.dock"])
      return;

    static BOOL initialized = NO;
    if (initialized)
      return;
    initialized = YES;

    SHARPENER_LOG(@"[DIAG] Installing ZKSwizzleGroup in: %@", bundleId);
    ZKSwizzleGroup(AppleSharpener);
    SHARPENER_LOG(@"[DIAG] ZKSwizzleGroup installed successfully");

    // Load persisted state: prioritize Config suite, fall back to CLI suite
    refreshSettings();

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          @try {
            setupWindowLogging();
          } @catch (NSException *e) {
          }
        });

    if (appFinishLaunchingObserver) {
      [[NSNotificationCenter defaultCenter]
          removeObserver:appFinishLaunchingObserver];
      appFinishLaunchingObserver = nil;
    }

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (!center)
      return;

    appFinishLaunchingObserver = [center
        addObserverForName:NSApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *__unused note) {
                  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                               (int64_t)(0.5 * NSEC_PER_SEC)),
                                 dispatch_get_main_queue(), ^{
                                   @autoreleasepool {
                                     @try {
                                       setupWindowLogging();
                                       if (disableWindowCornerRadius) {
                                         NSApplication *app =
                                             [NSApplication sharedApplication];
                                         for (NSWindow *window in app.windows) {
                                           if (isStandardAppWindow(window)) {
                                             applySquareCorners(window);
                                           }
                                         }
                                       }
                                     } @catch (NSException *e) {
                                     }
                                   }
                                 });
                }];

    // Fullscreen transition observers
    [center addObserverForName:NSWindowWillEnterFullScreenNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                      @try {
                        NSWindow *window = note.object;
                        if (window && [window isKindOfClass:[NSWindow class]]) {
                          setWindowMarkedFullscreen(window, YES);
                          restoreDefaultCorners(window);
                          applyBorderOverlay(window, window.isKeyWindow);
                        }
                      } @catch (NSException *e) {
                      }
                    }];

    // Fullscreen transition COMPLETE: sidebar glass layers are re-laid out
    // with system corner radii. Re-square them after a short delay so the
    // post-animation layout pass is also captured.
    [center addObserverForName:NSWindowDidEnterFullScreenNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                      @try {
                        NSWindow *window = note.object;
                        if (window && [window isKindOfClass:[NSWindow class]]) {
                          if ([sidebarMode isEqualToString:@"square"]) {
                            dispatch_after(
                                dispatch_time(DISPATCH_TIME_NOW,
                                              (int64_t)(0.15 * NSEC_PER_SEC)),
                                dispatch_get_main_queue(), ^{
                                  @try {
                                    applySpecificUIElementSharpening(window);
                                    [window displayIfNeeded];
                                  } @catch (NSException *e) {
                                  }
                                });
                          }
                        }
                      } @catch (NSException *e) {
                      }
                    }];

    [center addObserverForName:NSWindowDidExitFullScreenNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                      @try {
                        NSWindow *window = note.object;
                        if (window && [window isKindOfClass:[NSWindow class]]) {
                          setWindowMarkedFullscreen(window, NO);
                          if (disableWindowCornerRadius) {
                            applySquareCorners(window);
                          }
                          applyBorderOverlay(window, window.isKeyWindow);
                        }
                      } @catch (NSException *e) {
                      }
                    }];

    // Native macOS Workspace and Tiling observers: ensure border perfectly
    // tracks window movement/resizes that bypass standard setFrame routing.
    void (^syncBorderBlock)(NSNotification *) = ^(NSNotification *note) {
      NSWindow *w = note.object;
      if (windowBordersEnabled && w && isStandardAppWindow(w)) {
        initializeBorderTracking();
        ASBorderWindow *borderWin = [windowToBorderMap objectForKey:w];
        if (borderWin && !isWindowFullscreen(w)) {
          NSRect targetFrame = calculateBorderFrame(w.frame, windowBorderWidth);
          [CATransaction begin];
          [CATransaction setDisableActions:YES];
          [borderWin setFrame:targetFrame display:YES];
          [CATransaction commit];
        }
      }
    };
    [center addObserverForName:NSWindowDidMoveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:syncBorderBlock];
    [center addObserverForName:NSWindowDidResizeNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:syncBorderBlock];

    // Workspace change observers: hide borders during Space switching to avoid
    // flickering
    NSNotificationCenter *wsCenter =
        [[NSWorkspace sharedWorkspace] notificationCenter];
    [wsCenter
        addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *__unused note) {
                  isWorkspaceSwitching = YES;
                  // Hide all borders
                  for (NSWindow *w in [windowToBorderMap keyEnumerator]) {
                    ASBorderWindow *bw = [windowToBorderMap objectForKey:w];
                    [bw orderOut:nil];
                  }
                  // Restore borders after a short delay
                  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                               (int64_t)(0.4 * NSEC_PER_SEC)),
                                 dispatch_get_main_queue(), ^{
                                   isWorkspaceSwitching = NO;
                                   for (NSWindow *w in
                                        [NSApplication sharedApplication]
                                            .windows) {
                                     if (isStandardAppWindow(w)) {
                                       applyBorderOverlay(w, w.isKeyWindow);
                                     }
                                   }
                                 });
                }];

    dispatch_queue_t queue = dispatch_get_main_queue();
    // CLI Notification Listeners
    notify_register_dispatch("com.aspauldingcode.apple_sharpener.enabled",
                             &(int){0}, queue, ^(int token) {
                               (void)token;
                               refreshSettings();
                               toggleSquareCorners(0, 0, 0, 0);
                             });
    notify_register_dispatch(
        "com.aspauldingcode.apple_sharpener.windows.enabled", &(int){0}, queue,
        ^(int token) {
          (void)token;
          refreshSettings();
          toggleSquareCorners(0, 0, 0, 0);
        });
    notify_register_dispatch("com.aspauldingcode.apple_sharpener.set_radius",
                             &(int){0}, queue, ^(int token) {
                               (void)token;
                               refreshSettings();
                               toggleSquareCorners(0, 0, 0, 0);
                             });
    notify_register_dispatch(
        "com.aspauldingcode.apple_sharpener.windows.set_radius", &(int){0},
        queue, ^(int token) {
          (void)token;
          refreshSettings();
          toggleSquareCorners(0, 0, 0, 0);
        });
    notify_register_dispatch(
        "com.aspauldingcode.apple_sharpener.squircle.enabled", &(int){0}, queue,
        ^(int token) {
          (void)token;
          refreshSettings();
          toggleSquareCorners(0, 0, 0, 0);
        });
    notify_register_dispatch(
        "com.aspauldingcode.apple_sharpener.squircle.exponent", &(int){0},
        queue, ^(int token) {
          (void)token;
          refreshSettings();
          toggleSquareCorners(0, 0, 0, 0);
        });
    notify_register_dispatch(
        "com.aspauldingcode.apple_sharpener.windows.shadows", &(int){0}, queue,
        ^(int token) {
          (void)token;
          refreshSettings();
          toggleSquareCorners(0, 0, 0, 0);
        });

    // Also listen for DistributedNotificationCenter from the GUI
    [[NSDistributedNotificationCenter defaultCenter]
        addObserverForName:@"com.aspauldingcode.apple_sharpener.modules.update"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *__unused note) {
                  refreshSettings();
                  toggleSquareCorners(0, 0, 0, 0);
                }];

    // Listen for low-level Darwin notification from CLI/Helper
    notify_register_dispatch("com.aspauldingcode.apple_sharpener.modules.update",
                             &(int){0}, queue, ^(int token) {
                               (void)token;
                               refreshSettings();
                               toggleSquareCorners(0, 0, 0, 0);
                             });

  } @catch (NSException *e) {
  }
}

#pragma mark - Swizzled NSWindow

ZKSwizzleInterfaceGroup(AS_NSWindow_CornerRadius, NSWindow, NSWindow,
                        AppleSharpener) @implementation AS_NSWindow_CornerRadius

- (void)setHasShadow:(BOOL)hasShadow {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, hasShadow);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow((NSWindow *)self);
  if (disableWindowCornerRadius && !s.shadows &&
      isStandardAppWindow((NSWindow *)self)) {
    ZKOrig(void, NO);
  } else {
    ZKOrig(void, hasShadow);
  }
}

- (void)invalidateShadow {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow((NSWindow *)self);
  if (disableWindowCornerRadius && !s.shadows &&
      isStandardAppWindow((NSWindow *)self)) {
    return;
  }
  ZKOrig(void);
}

/// macOS 26+ still paints a titlebar “rim” from shadow parameters when
/// `hasShadow` is NO. Returning nil matches disabling shadow metadata entirely.
- (id)shadowParameters {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  SharpenerWindowSettings s = getSettingsForWindow((NSWindow *)self);
  if (disableWindowCornerRadius && !s.shadows &&
      isStandardAppWindow((NSWindow *)self)) {
    return nil;
  }
  return ZKOrig(id);
}

- (void)orderFront:(id)sender {
  ZKOrig(void, sender);

  if (disableWindowCornerRadius) {
    applySquareCorners((NSWindow *)self);
  }
}

- (void)makeKeyAndOrderFront:(id)sender {
  ZKOrig(void, sender);

  if (disableWindowCornerRadius) {
    applySquareCorners((NSWindow *)self);
  }
}

- (void)orderFrontRegardless {
  ZKOrig(void);

  if (disableWindowCornerRadius) {
    applySquareCorners((NSWindow *)self);
  }
}

- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWin {
  ZKOrig(void, place, otherWin);

  if (disableWindowCornerRadius && place != NSWindowOut) {
    applySquareCorners((NSWindow *)self);
  }
}

- (void)becomeKeyWindow {
  ZKOrig(void);

  if (disableWindowCornerRadius) {
    applySquareCorners((NSWindow *)self);
  }
  if (windowBordersEnabled) {
    applyBorderOverlay((NSWindow *)self, YES);
  }
}

- (void)resignKeyWindow {
  ZKOrig(void);

  if (disableWindowCornerRadius) {
    applySquareCorners((NSWindow *)self);
  }
  if (windowBordersEnabled) {
    applyBorderOverlay((NSWindow *)self, NO);
  }
}

- (void)setFrame:(NSRect)frameRect display:(BOOL)flag {
  static __thread BOOL inSetFrame = NO;
  if (inSetFrame) {
    ZKOrig(void, frameRect, flag);
    return;
  }
  inSetFrame = YES;
  @try {
    ZKOrig(void, frameRect, flag);
  } @catch (NSException *e) {
  }

  // Update border window frame if it exists BEFORE applying square corners
  if (windowBordersEnabled) {
    initializeBorderTracking();
    ASBorderWindow *borderWin =
        [windowToBorderMap objectForKey:(NSWindow *)self];
    if (borderWin) {
      NSRect targetFrame = calculateBorderFrame(frameRect, windowBorderWidth);
      [CATransaction begin];
      [CATransaction setDisableActions:YES];
      [borderWin setFrame:targetFrame display:flag];
      borderWin.level = ((NSWindow *)self).level;
      [CATransaction commit];
    }
  }

  if (disableWindowCornerRadius) {
    applySquareCorners((NSWindow *)self);
  }

  inSetFrame = NO;
}

- (void)_updateCornerMask {
  ZKOrig(void);
  if (disableWindowCornerRadius && isStandardAppWindow((NSWindow *)self)) {
    applySquareCorners((NSWindow *)self);
  }
}

- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    // Still apply window-level KVC corners for Chromium stability
    applySquareCorners((NSWindow *)self);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow((NSWindow *)self);
  if (!s.enabled || !isStandardAppWindow((NSWindow *)self) ||
      isApplyingSquareCorners((NSWindow *)self)) {
    ZKOrig(void, radius);
    return;
  }

  CGFloat effectiveRadius = (CGFloat)s.radius;
  if (effectiveRadius == 0)
    effectiveRadius = kSharpenerNearZeroRadius;

  CGFloat displayRadius = effectiveRadius;
  if (s.squircle && s.radius > 0) {
    displayRadius = effectiveRadius * (s.squircleExponent / 2.0);
  }

  NSView *rootView = ((NSWindow *)self).contentView.superview
                         ?: ((NSWindow *)self).contentView;
  if (rootView) {
    CGFloat maxR = MIN(rootView.bounds.size.width / 2.0,
                       rootView.bounds.size.height / 2.0);
    displayRadius = MIN(displayRadius, maxR);
  }
  if (displayRadius <= 0)
    displayRadius = kSharpenerNearZeroRadius;

  ZKOrig(void, displayRadius);

  applySquareCorners((NSWindow *)self);
}

- (id)_cornerMask {
  if (disableWindowCornerRadius && isStandardAppWindow((NSWindow *)self)) {
    return nil;
  }
  return ZKOrig(id);
}

- (void)toggleFullScreen:(id)sender {
  if (disableWindowCornerRadius) {
    restoreDefaultCorners((NSWindow *)self);
  }
  ZKOrig(void, sender);
}

@end

#pragma mark - Swizzled NSPanel

ZKSwizzleInterfaceGroup(AS_NSPanel_CornerRadius, NSPanel, NSWindow,
                        AppleSharpener) @implementation AS_NSPanel_CornerRadius

- (void)orderFront:(id)sender {
  ZKOrig(void, sender);

  if (disableWindowCornerRadius) {
    applySquareCorners((NSWindow *)self);
  }
}

- (void)makeKeyAndOrderFront:(id)sender {
  ZKOrig(void, sender);

  if (disableWindowCornerRadius) {
    applySquareCorners((NSWindow *)self);
  }
}

- (void)orderFrontRegardless {
  ZKOrig(void);

  if (disableWindowCornerRadius) {
    applySquareCorners((NSWindow *)self);
  }
}

- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWin {
  ZKOrig(void, place, otherWin);

  if (disableWindowCornerRadius && place != NSWindowOut) {
    applySquareCorners((NSWindow *)self);
  }
}

- (void)becomeKeyWindow {
  ZKOrig(void);

  if (disableWindowCornerRadius) {
    applySquareCorners((NSWindow *)self);
  }
}

- (void)setFrame:(NSRect)frameRect display:(BOOL)flag {
  static __thread BOOL inSetFrame_Panel = NO;
  if (inSetFrame_Panel) {
    ZKOrig(void, frameRect, flag);
    return;
  }
  inSetFrame_Panel = YES;
  @try {
    ZKOrig(void, frameRect, flag);
  } @catch (NSException *e) {
  }

  // Update border window frame if it exists BEFORE applying square corners
  if (windowBordersEnabled) {
    initializeBorderTracking();
    ASBorderWindow *borderWin =
        [windowToBorderMap objectForKey:(NSWindow *)self];
    if (borderWin) {
      NSRect targetFrame = calculateBorderFrame(frameRect, windowBorderWidth);
      [CATransaction begin];
      [CATransaction setDisableActions:YES];
      [borderWin setFrame:targetFrame display:flag];
      borderWin.level = ((NSWindow *)self).level;
      [CATransaction commit];
    }
  }

  if (disableWindowCornerRadius) {
    applySquareCorners((NSWindow *)self);
  }
  inSetFrame_Panel = NO;
}

@end

#pragma mark - CALayer Swizzles (Oowm style)

ZKSwizzleInterfaceGroup(AS_CALayer_Square, CALayer, CALayer, AppleSharpener)
    @implementation AS_CALayer_Square

- (void)layoutSublayers {
  ZKOrig(void);

  if ([(CALayer *)self _shouldBeSquare]) {
    ((CALayer *)self).cornerRadius = kSharpenerNearZeroRadius;

    if (((CALayer *)self).mask) {
      ((CALayer *)self).mask.cornerRadius = kSharpenerNearZeroRadius;
    }
  }
}

- (void)setCornerRadius:(CGFloat)radius {
  if ([(CALayer *)self _shouldBeSquare]) {
    ZKOrig(void, kSharpenerNearZeroRadius);
  } else {
    ZKOrig(void, radius);
  }
}

- (BOOL)_shouldBeSquare {
  if (sharpener_is_chromium_based_process())
    return NO;

  CALayer *layer = (CALayer *)self;

  NSString *lClass = NSStringFromClass(layer.class);
  if ([lClass isEqualToString:@"CABackdropLayer"] ||
      [lClass isEqualToString:@"CASDFElementLayer"] ||
      [lClass containsString:@"SDF"]) {
    return NO;
  }

  BOOL isMenu = NO;
  for (CALayer *cur = layer; cur != nil; cur = cur.superlayer) {
    id del = cur.delegate;
    if (!del || ![del isKindOfClass:[NSView class]])
      continue;
    NSString *cvn = NSStringFromClass([(NSView *)del class]);
    if ([cvn containsString:@"Menu"] || [cvn containsString:@"PopUp"] ||
        [cvn containsString:@"Shadow"] || [cvn containsString:@"Tooltip"] ||
        [cvn containsString:@"Overlay"] || [cvn containsString:@"Popover"]) {
      isMenu = YES;
      break;
    }
  }
  if (isMenu)
    return NO;

  SharpenerChromeFlags flags;
  SharpenerChromeFlagsReset(&flags);
  SharpenerMergeChromeFlagsFromCALayer(layer, &flags);

  NSWindow *windowToUse = SharpenerWindowForCALayer(layer);
  if (!windowToUse)
    return NO;

  if (!isStandardAppWindow(windowToUse) && !isWindowFullscreen(windowToUse))
    return NO;

  NSString *wClass = NSStringFromClass(windowToUse.class);
  if ([wClass containsString:@"Menu"] ||
      [wClass containsString:@"CarbonMenu"] ||
      [wClass containsString:@"Overlay"] || [wClass containsString:@"Popup"]) {
    return NO;
  }

  SharpenerWindowSettings s = getSettingsForWindow(windowToUse);

  if (isWindowFullscreen(windowToUse)) {
    if (flags.toolbarTitlebar)
      return [s.toolbar isEqualToString:@"square"];
    if (flags.sidebar)
      return [s.sidebar isEqualToString:@"square"];
  }

  if (flags.trafficLight)
    return [s.trafficLights isEqualToString:@"square"];
  if (flags.toolbarTitlebar)
    return [s.toolbar isEqualToString:@"square"];
  if (flags.sidebar)
    return [s.sidebar isEqualToString:@"square"];

  return NO;
}

@end

#pragma mark - UI Element Swizzles

// 1. Traffic Lights (_NSThemeWidget, NSTrafficLightView)
#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_TrafficLight_CornerRadius, _NSThemeWidget, NSView,
                        AppleSharpener)
    @implementation AS_TrafficLight_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  if ([s.trafficLights isEqualToString:@"square"])
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void, [s.trafficLights isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius);
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void, [s.trafficLights isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius);
}
@end
#pragma clang diagnostic pop

#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_TrafficLightView_CornerRadius, NSTrafficLightView,
                        NSView, AppleSharpener)
    @implementation AS_TrafficLightView_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  if ([s.trafficLights isEqualToString:@"square"])
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void, [s.trafficLights isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius);
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void, [s.trafficLights isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius);
}
@end
#pragma clang diagnostic pop

// 2. Sidebar (NSSidebarView, _NSFullHeightSideBarSeparatorView)
#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_Sidebar_CornerRadius, NSSidebarView, NSView,
                        AppleSharpener) @implementation AS_Sidebar_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  if ([s.sidebar isEqualToString:@"square"])
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void,
         (CGFloat)([s.sidebar isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius));
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void,
         (CGFloat)([s.sidebar isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius));
}
@end
#pragma clang diagnostic pop

#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_SidebarSeparator_CornerRadius,
                        _NSFullHeightSideBarSeparatorView, NSView,
                        AppleSharpener)
    @implementation AS_SidebarSeparator_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  if ([s.sidebar isEqualToString:@"square"])
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void,
         (CGFloat)([s.sidebar isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius));
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void,
         (CGFloat)([s.sidebar isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius));
}
@end
#pragma clang diagnostic pop

#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_VisualEffectSidebar_CornerRadius, NSVisualEffectView,
                        NSView, AppleSharpener)
    @implementation AS_VisualEffectSidebar_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  if ([s.sidebar isEqualToString:@"square"] &&
      [(NSVisualEffectView *)self material] == NSVisualEffectMaterialSidebar)
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void, (CGFloat)([s.sidebar isEqualToString:@"square"] &&
                                 [(NSVisualEffectView *)self material] ==
                                     NSVisualEffectMaterialSidebar
                             ? kSharpenerNearZeroRadius
                             : radius));
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void, (CGFloat)([s.sidebar isEqualToString:@"square"] &&
                                 [(NSVisualEffectView *)self material] ==
                                     NSVisualEffectMaterialSidebar
                             ? kSharpenerNearZeroRadius
                             : radius));
}
@end
#pragma clang diagnostic pop

// 2b. Liquid Glass sidebar containers (macOS 26+)
// NSContainerConcentricGlassEffectView — outer container for concentric glass
#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_ConcentricGlass_CornerRadius,
                        NSContainerConcentricGlassEffectView, NSView,
                        AppleSharpener)
    @implementation AS_ConcentricGlass_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  if (sharpener_square_liquid_container((NSView *)self))
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  ZKOrig(void, (CGFloat)(sharpener_square_liquid_container((NSView *)self)
                             ? kSharpenerNearZeroRadius
                             : radius));
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  ZKOrig(void, (CGFloat)(sharpener_square_liquid_container((NSView *)self)
                             ? kSharpenerNearZeroRadius
                             : radius));
}
@end
#pragma clang diagnostic pop

// NSBlurryAlleywayView — inner alleyway blur behind sidebar
#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_AlleywayView_CornerRadius, NSBlurryAlleywayView,
                        NSView, AppleSharpener)
    @implementation AS_AlleywayView_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  if (sharpener_square_liquid_container((NSView *)self))
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  ZKOrig(void, (CGFloat)(sharpener_square_liquid_container((NSView *)self)
                             ? kSharpenerNearZeroRadius
                             : radius));
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  ZKOrig(void, (CGFloat)(sharpener_square_liquid_container((NSView *)self)
                             ? kSharpenerNearZeroRadius
                             : radius));
}
@end
#pragma clang diagnostic pop

// NSScrollPocket — scroll pocket in the sidebar (visible top/bottom in
// fullscreen)
#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_ScrollPocket_CornerRadius, NSScrollPocket, NSView,
                        AppleSharpener)
    @implementation AS_ScrollPocket_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  if (sharpener_square_liquid_container((NSView *)self))
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  ZKOrig(void, (CGFloat)(sharpener_square_liquid_container((NSView *)self)
                             ? kSharpenerNearZeroRadius
                             : radius));
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  ZKOrig(void, (CGFloat)(sharpener_square_liquid_container((NSView *)self)
                             ? kSharpenerNearZeroRadius
                             : radius));
}
@end
#pragma clang diagnostic pop

// _NSCoreHostingView — SwiftUI hosting view for the top glass effect
#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_CoreHostingView_CornerRadius, _NSCoreHostingView,
                        NSView, AppleSharpener)
    @implementation AS_CoreHostingView_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  if (sharpener_square_liquid_container((NSView *)self))
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  ZKOrig(void, (CGFloat)(sharpener_square_liquid_container((NSView *)self)
                             ? kSharpenerNearZeroRadius
                             : radius));
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  ZKOrig(void, (CGFloat)(sharpener_square_liquid_container((NSView *)self)
                             ? kSharpenerNearZeroRadius
                             : radius));
}
@end
#pragma clang diagnostic pop

// NSTitlebarSeparatorView — Separator line beside the top glass effect
#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_TitlebarSeparator_CornerRadius,
                        NSTitlebarSeparatorView, NSView, AppleSharpener)
    @implementation AS_TitlebarSeparator_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  if (sharpener_square_toolbar_policy((NSView *)self))
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  ZKOrig(void, (CGFloat)(sharpener_square_toolbar_policy((NSView *)self)
                             ? kSharpenerNearZeroRadius
                             : radius));
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  ZKOrig(void, (CGFloat)(sharpener_square_toolbar_policy((NSView *)self)
                             ? kSharpenerNearZeroRadius
                             : radius));
}
@end
#pragma clang diagnostic pop

// 3. Toolbar (NSToolbarItemViewer, _NSToolbarSeparatorView, _NSToolbarClipView)
#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_ToolbarItem_CornerRadius, NSToolbarItemViewer,
                        NSView, AppleSharpener)
    @implementation AS_ToolbarItem_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  if ([s.toolbar isEqualToString:@"square"])
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void,
         (CGFloat)([s.toolbar isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius));
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void,
         (CGFloat)([s.toolbar isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius));
}
@end
#pragma clang diagnostic pop

#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_ToolbarSeparator_CornerRadius,
                        _NSToolbarSeparatorView, NSView, AppleSharpener)
    @implementation AS_ToolbarSeparator_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  if ([s.toolbar isEqualToString:@"square"])
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void,
         (CGFloat)([s.toolbar isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius));
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void,
         (CGFloat)([s.toolbar isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius));
}
@end
#pragma clang diagnostic pop

#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_ToolbarClipView_CornerRadius, _NSToolbarClipView,
                        NSView, AppleSharpener)
    @implementation AS_ToolbarClipView_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  if ([s.toolbar isEqualToString:@"square"])
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void,
         (CGFloat)([s.toolbar isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius));
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  SharpenerWindowSettings s = getSettingsForWindow(((NSView *)self).window);
  ZKOrig(void,
         (CGFloat)([s.toolbar isEqualToString:@"square"] ? kSharpenerNearZeroRadius : radius));
}
@end
#pragma clang diagnostic pop

// 2d. NSGlassEffectView (macOS Tahoe sidebar glass)
#pragma clang diagnostic push
ZKSwizzleInterfaceGroup(AS_GlassEffect_CornerRadius, NSGlassEffectView, NSView,
                        AppleSharpener)
    @implementation AS_GlassEffect_CornerRadius
- (id)_cornerMask {
  if (sharpener_is_chromium_based_process())
    return ZKOrig(id);
  if (sharpener_square_ns_glass_effect((NSGlassEffectView *)self))
    return nil;
  return ZKOrig(id);
}
- (void)_setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  ZKOrig(void, (CGFloat)(sharpener_square_ns_glass_effect(
                             (NSGlassEffectView *)self)
                             ? kSharpenerNearZeroRadius
                             : radius));
}
- (void)setCornerRadius:(CGFloat)radius {
  if (sharpener_is_chromium_based_process()) {
    ZKOrig(void, radius);
    return;
  }
  ZKOrig(void, (CGFloat)(sharpener_square_ns_glass_effect(
                             (NSGlassEffectView *)self)
                             ? kSharpenerNearZeroRadius
                             : radius));
}
@end
#pragma clang diagnostic pop
