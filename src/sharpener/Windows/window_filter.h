/**
 * Apple Sharpener: Window Filtering Utilities
 *
 * Provides a comprehensive set of inline helpers to determine which windows
 * should be modified by the sharpener. This includes logic to exclude
 * system-critical overlays, Mission Control, and other non-standard windows.
 */

#ifndef WINDOW_FILTER_H
#define WINDOW_FILTER_H

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

/**
 * Window filtering utilities for apple-sharpener
 *
 * Shared window filtering logic used by both sharpener and shadow code.
 * Contains all standard window checks and utilities.
 *
 * This header provides common window filtering functions that are used
 * by both the window sharpening code (window.m) and shadow/red frame code
 * (window.shadow.m).
 *
 * IMPORTANT: This is a GLOBAL tweak - applies to ALL applications including
 * Chromium and Electron.
 */

/**
 * Shared fullscreen tracking flag using associated objects.
 * Used to reliably track fullscreen state during transition animations
 * when the window styleMask might be inconsistent.
 */
static const void *kASWindowIsFullscreenKey = &kASWindowIsFullscreenKey;

static inline BOOL isWindowMarkedFullscreen(NSWindow *window) {
  if (!window)
    return NO;
  return [objc_getAssociatedObject(window, kASWindowIsFullscreenKey) boolValue];
}

static inline void setWindowMarkedFullscreen(NSWindow *window,
                                             BOOL fullscreen) {
  if (!window)
    return;
  objc_setAssociatedObject(window, kASWindowIsFullscreenKey, @(fullscreen),
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/**
 * Check if a window is fullscreen (including titlebar-only fullscreen)
 */
static inline BOOL isWindowFullscreen(NSWindow *window) {
  if (!window)
    return NO;

  // 1. Check our reliable notification-driven flag first
  if (isWindowMarkedFullscreen(window))
    return YES;

  @try {
    NSString *className = NSStringFromClass([window class]);

    // 2. Check for specific fullscreen helper windows
    // Catch-all for system windows like NSTitlebarFullScreenWindow,
    // NSToolbarFullScreenWindow, etc.
    if ([className containsString:@"FullScreenWindow"]) {
      return YES;
    }

    // 3. Check if parent window is fullscreen
    if (window.parentWindow &&
        (window.parentWindow.styleMask & NSWindowStyleMaskFullScreen)) {
      return YES;
    }

    // 4. Check style mask
    if ((window.styleMask & NSWindowStyleMaskFullScreen) ==
        NSWindowStyleMaskFullScreen)
      return YES;

    // Avoid respondsToSelector: and NSInvocation during early initialization
    // to prevent potential recursion or crashes in complex apps like Zoom.
    // We'll rely on styleMask for now, which is usually sufficient.

    // 5. Check for fullscreen titlebar (window fills screen but may have
    // titlebar)
    NSScreen *screen = window.screen ?: [NSScreen mainScreen];
    if (screen) {
      NSRect screenFrame = screen.frame;
      NSRect windowFrame = window.frame;
      // Allow small tolerance for menu bar
      if (fabs(windowFrame.origin.x - screenFrame.origin.x) < 1 &&
          fabs(windowFrame.origin.y - screenFrame.origin.y) < 1 &&
          fabs(windowFrame.size.width - screenFrame.size.width) < 1 &&
          fabs(windowFrame.size.height - screenFrame.size.height) < 1) {
        return YES;
      }
    }
  } @catch (NSException *e) {
  }
  return NO;
}

/**
 * Check if a window is a Dock tile right-click menu (the blue box frame around
 * dock icons)
 */
static inline BOOL isDockTileMenuWindow(NSWindow *window) {
  if (!window)
    return NO;
  @try {
    NSString *className = NSStringFromClass([window class]);

    // Check for Dock-related window class names
    if ([className containsString:@"Dock"] ||
        [className containsString:@"DockTile"] ||
        [className containsString:@"DockMenu"]) {
      return YES;
    }

    // Dock tile menus are typically small borderless windows at high levels
    NSWindowLevel level = window.level;
    if (level >= NSPopUpMenuWindowLevel) {
      // Check if it's a small borderless window (typical of dock tile menu)
      // The blue box frame is usually small and appears near the dock
      NSRect frame = window.frame;
      if ((window.styleMask & NSWindowStyleMaskTitled) == 0 &&
          (window.styleMask & NSWindowStyleMaskBorderless) != 0 &&
          frame.size.width < 500 && frame.size.height < 500) {
        // Additional check: if window is near bottom of screen (dock area)
        NSScreen *screen = window.screen ?: [NSScreen mainScreen];
        if (screen) {
          NSRect screenFrame = screen.frame;
          // Dock is typically at bottom, so check if window is near bottom
          CGFloat distanceFromBottom = frame.origin.y - screenFrame.origin.y;
          if (distanceFromBottom < screenFrame.size.height * 0.3) {
            return YES;
          }
        }
        // If we can't check position, still exclude small high-level borderless
        // windows
        return YES;
      }
    }
  } @catch (NSException *e) {
  }
  return NO;
}

/**
 * Check if a window is Exposé or Mission Control overlay
 * Includes workspace switcher buttons, xpose labels, desktop thumbnails,
 * and any window created by the Dock for Mission Control purposes.
 */
static inline BOOL isExposeOrMissionControlWindow(NSWindow *window) {
  if (!window)
    return NO;
  @try {
    // If we're in the Dock process, ALL windows are Mission Control / Dock UI.
    // The only thing we modify in the Dock is the dock bar itself (via dock.m's
    // CALayer hook), not any NSWindow.
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleId isEqualToString:@"com.apple.dock"]) {
      return YES;
    }

    NSString *className = NSStringFromClass([window class]);

    // Check for Exposé/Mission Control related class names
    // Use SPECIFIC patterns — avoid broad substrings like "Space",
    // "Desktop", "Label" that would false-positive on normal app windows.
    if ([className containsString:@"Expose"] ||
        [className containsString:@"Exposé"] ||
        [className containsString:@"MissionControl"] ||
        [className containsString:@"Mission Control"] ||
        [className containsString:@"Spaces"] ||
        [className containsString:@"Workspace"] ||
        [className containsString:@"Switcher"] ||
        [className containsString:@"DOCKWindow"] ||
        [className containsString:@"DOCKExpose"] ||
        [className containsString:@"_DKWindow"] ||
        [className containsString:@"DockExtra"] ||
        [className containsString:@"Thumbnail"]) {
      return YES;
    }

    // Check for workspace switcher buttons and xpose labels
    // These are typically smaller windows at high levels
    NSWindowLevel level = window.level;
    if (level >= NSMainMenuWindowLevel) {
      NSRect windowFrame = window.frame;
      NSScreen *screen = window.screen ?: [NSScreen mainScreen];
      if (screen) {
        NSRect screenFrame = screen.frame;
        CGFloat screenArea = screenFrame.size.width * screenFrame.size.height;
        CGFloat windowArea = windowFrame.size.width * windowFrame.size.height;
        // If window covers more than 80% of screen, likely Exposé/Mission
        // Control overlay. Or if it's a small high-level window, likely a
        // switcher button or label.
        if (windowArea > screenArea * 0.8 ||
            (windowArea < screenArea * 0.1 && level >= NSMainMenuWindowLevel)) {
          return YES;
        }
      }
    }
  } @catch (NSException *e) {
  }
  return NO;
}

/**
 * Check if a window is a Spotlight window
 */
static inline BOOL isSpotlightWindow(NSWindow *window) {
  if (!window)
    return NO;
  @try {
    NSString *className = NSStringFromClass([window class]);

    // Check for Spotlight-related class names
    // Note: removed broad "SFL" check — it could match unrelated classes.
    if ([className containsString:@"Spotlight"] ||
        [className containsString:@"Siri"]) {
      return YES;
    }

    // Spotlight windows are typically at high levels and may be borderless
    NSWindowLevel level = window.level;
    if (level >= NSMainMenuWindowLevel) {
      // Spotlight search window is typically a borderless window near the top
      // of screen
      NSScreen *screen = window.screen ?: [NSScreen mainScreen];
      if (screen) {
        NSRect screenFrame = screen.frame;
        NSRect windowFrame = window.frame;
        // Check if window is near the top center (typical Spotlight position)
        CGFloat centerX = screenFrame.origin.x + screenFrame.size.width / 2;
        CGFloat windowCenterX =
            windowFrame.origin.x + windowFrame.size.width / 2;
        CGFloat distanceFromTop =
            (screenFrame.origin.y + screenFrame.size.height) -
            (windowFrame.origin.y + windowFrame.size.height);

        if (fabs(windowCenterX - centerX) < screenFrame.size.width * 0.3 &&
            distanceFromTop < screenFrame.size.height * 0.2 &&
            (window.styleMask & NSWindowStyleMaskBorderless) != 0) {
          return YES;
        }
      }
    }
  } @catch (NSException *e) {
  }
  return NO;
}

/**
 * Check if a window is a Control Center window
 */
static inline BOOL isControlCenterWindow(NSWindow *window) {
  if (!window)
    return NO;
  @try {
    NSString *className = NSStringFromClass([window class]);

    // Check for Control Center-related class names
    // Note: removed broad "CC" check — it matched any class with "CC"
    // anywhere (e.g. Cocoa internal classes), causing false exclusions.
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleId isEqualToString:@"com.apple.controlcenter"]) {
      return YES;
    }
    if ([className containsString:@"ControlCenter"] ||
        [className containsString:@"Control Center"]) {
      return YES;
    }

    // Control Center windows are typically at high levels and borderless
    NSWindowLevel level = window.level;
    if (level >= NSMainMenuWindowLevel) {
      // Control Center typically appears from the right side of the screen
      NSScreen *screen = window.screen ?: [NSScreen mainScreen];
      if (screen) {
        NSRect screenFrame = screen.frame;
        NSRect windowFrame = window.frame;
        // Check if window is near the right edge (typical Control Center
        // position)
        CGFloat distanceFromRight =
            (screenFrame.origin.x + screenFrame.size.width) -
            (windowFrame.origin.x + windowFrame.size.width);
        if (distanceFromRight < 50 &&
            (window.styleMask & NSWindowStyleMaskBorderless) != 0) {
          return YES;
        }
      }
    }
  } @catch (NSException *e) {
  }
  return NO;
}

/**
 * Check if a window is a menubar applet, menubar background, menubar group, or
 * menubar itself
 */
static inline BOOL isMenubarWindow(NSWindow *window) {
  if (!window)
    return NO;
  @try {
    NSString *className = NSStringFromClass([window class]);

    // Check for menubar-related class names
    if ([className containsString:@"Menubar"] ||
        [className containsString:@"MenuBar"] ||
        [className containsString:@"NSStatusBar"] ||
        [className containsString:@"StatusBar"] ||
        [className containsString:@"Applet"] ||
        [className containsString:@"MenuExtra"]) {
      return YES;
    }

    // Menubar windows are at the menubar level or above
    NSWindowLevel level = window.level;
    if (level >= NSMainMenuWindowLevel) {
      // Check if window is at the top of the screen (menubar area)
      NSScreen *screen = window.screen ?: [NSScreen mainScreen];
      if (screen) {
        NSRect screenFrame = screen.frame;
        NSRect windowFrame = window.frame;
        // Menubar is at the top of the screen
        CGFloat distanceFromTop =
            (screenFrame.origin.y + screenFrame.size.height) -
            (windowFrame.origin.y + windowFrame.size.height);
        // Menubar is typically 22-25 pixels tall, allow some tolerance
        if (distanceFromTop < 50 && windowFrame.size.height < 50) {
          return YES;
        }
      }
    }
  } @catch (NSException *e) {
  }
  return NO;
}

/**
 * Check if a window is a context menu or popup menu
 */
static inline BOOL isContextMenuWindow(NSWindow *window) {
  if (!window)
    return NO;
  @try {
    NSString *className = NSStringFromClass([window class]);

    // Check for specific context menu / popup window class names.
    // Note: removed broad "Menu" check — it matched any class containing
    // "Menu" (e.g. app controller classes), causing false exclusions.
    if ([className isEqualToString:@"NSCarbonMenuWindow"] ||
        [className isEqualToString:@"NSMenuWindowManagerWindow"] ||
        [className containsString:@"_NSPopover"] ||
        [className containsString:@"Popup"] ||
        [className containsString:@"Tooltip"]) {
      return YES;
    }

    // Context menus typically have very high window levels
    NSWindowLevel level = window.level;
    if (level >= NSPopUpMenuWindowLevel) {
      return YES;
    }

    // Check if window has no titlebar and is very small (typical of context
    // menus)
    if ((window.styleMask & NSWindowStyleMaskTitled) == 0 &&
        window.frame.size.width < 200 && window.frame.size.height < 300) {
      // Additional check: if it's a borderless window at a high level, likely a
      // menu
      if (level > NSStatusWindowLevel) {
        return YES;
      }
    }
  } @catch (NSException *e) {
  }
  return NO;
}

/**
 * Check if a window should receive modifications.
 *
 * This is a GLOBAL tweak - applies to ALL applications including Chromium and
 * Electron.
 *
 * Applies to ALL windows except:
 * - Sheets (modal dialogs attached to parent windows)
 * - Child windows (windows with a parent window)
 * - Fullscreen windows (including fullscreen titlebar)
 * - Context menus and popup menus
 * - Dock tile right-click menus (blue box frame around dock icons)
 * - Exposé and Mission Control windows (including workspace switcher buttons
 * and xpose labels)
 * - Spotlight windows
 * - Control Center windows
 * - Menubar applets, backgrounds, groups, and menubar itself
 * - Very high-level system windows (menubar level and above)
 *
 * @param window The window to check
 * @return YES if the window should receive modifications, NO otherwise
 */
static inline BOOL isStandardAppWindow(NSWindow *window) {
  if (!window)
    return NO;

  @try {
    // We now allow more windows because we hook at orderFront: where windows
    // are fully formed. However, we still exclude explicitly problematic
    // parents like sheets.
    if (window.sheetParent != nil)
      return NO;

    // Explicitly exclude our own helper windows by class name
    NSString *className = NSStringFromClass([window class]);
    if ([className isEqualToString:@"RedFrameWindow"] ||
        [className isEqualToString:@"ASBorderWindow"] ||
        [className isEqualToString:@"SUIKBHUDScreen"]) {
      return NO;
    }

    // Exclude fullscreen windows (including fullscreen titlebar)
    if (isWindowFullscreen(window)) {
      return NO;
    }

    // Exclude context menus and popup menus
    if (isContextMenuWindow(window)) {
      return NO;
    }

    // Exclude Dock tile right-click menu (blue box frame around dock icons)
    if (isDockTileMenuWindow(window)) {
      return NO;
    }

    // Exclude Exposé and Mission Control windows (including workspace switcher
    // buttons and xpose labels)
    if (isExposeOrMissionControlWindow(window)) {
      return NO;
    }

    // Exclude Spotlight windows
    if (isSpotlightWindow(window)) {
      return NO;
    }

    // Exclude Control Center windows
    if (isControlCenterWindow(window)) {
      return NO;
    }

    // Exclude menubar applets, backgrounds, groups, and menubar itself
    if (isMenubarWindow(window)) {
      return NO;
    }

    NSWindowLevel level = window.level;

    // Only exclude very high-level system windows (menubar and above)
    // Allow all other windows including status-level windows
    if (level > NSStatusWindowLevel) {
      return NO;
    }

    // All other windows are allowed (Settings, SwiftUI, Electron main windows,
    // etc.)
    return YES;
  } @catch (NSException *exception) {
    // Don't process if we can't validate - fail safe by excluding
    return NO;
  }
}

/**
 * Check if a window is a system UI window (menubar, etc.)
 * Minimal check - only excludes very high-level system windows.
 *
 * @param window The window to check
 * @return YES if the window is system UI, NO otherwise
 */
static inline BOOL isSystemUIWindow(NSWindow *window) {
  if (!window)
    return NO;

  @try {
    // Exclude fullscreen windows
    if (isWindowFullscreen(window)) {
      return YES;
    }

    // Exclude context menus
    if (isContextMenuWindow(window)) {
      return YES;
    }

    NSWindowLevel level = window.level;

    // Only exclude very high-level system windows (menubar and above)
    // All app windows (including Settings, SwiftUI, Electron) are NOT system UI
    if (level > NSStatusWindowLevel) {
      return YES;
    }

    // Exclude child windows/subviews
    if ([window parentWindow] != nil &&
        (window.styleMask & NSWindowStyleMaskTitled) == 0) {
      return YES;
    }
  } @catch (NSException *e) {
  }

  return NO;
}

#endif /* WINDOW_FILTER_H */
