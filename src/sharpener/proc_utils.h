#ifndef SHARPENER_PROC_UTILS_H
#define SHARPENER_PROC_UTILS_H

#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <string.h>

/**
 * Process-level filtering for apple-sharpener
 *
 * Ported from Oowm's proc_utils.h — prevents code injection into
 * System Settings extension/helper processes that would otherwise crash.
 *
 * System Settings on macOS runs its preference panes as separate XPC
 * extension processes (General, Desktop, Wallpaper, ScreenSaver, etc.).
 * Swizzling NSWindow in those processes causes crashes because they have
 * different lifecycle expectations. We whitelist the MAIN System Settings
 * app but block all its helper/extension sub-processes.
 */

/**
 * Returns YES if the current process is an extension/helper that should
 * NOT be modified. Returns NO for the main System Settings app itself
 * (which is safe to sharpen).
 */
static inline BOOL sharpener_is_extension_process(void) {
  static BOOL isExt = NO;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *procName = [[NSProcessInfo processInfo] processName];
    NSString *execPath = [[NSBundle mainBundle] executablePath];
    NSString *execName = [execPath lastPathComponent];

    // Explicitly whitelist the main System Settings app
    if ([execName isEqualToString:@"System Settings"] ||
        [bundleID isEqualToString:@"com.apple.systempreferences"]) {
      isExt = NO;
      return;
    }

    // Block all other System Settings helpers/extensions by process name
    if ([procName containsString:@"Settings"] ||
        [procName isEqualToString:@"General"] ||
        [procName isEqualToString:@"Desktop"] ||
        [procName isEqualToString:@"ScreenSaver"] ||
        [procName isEqualToString:@"Wallpaper"]) {
      isExt = YES;
    }

    // Block XPC services, ViewBridge hosts, and extension processes
    if (!bundleID || [bundleID containsString:@".xpc"] ||
        [bundleID containsString:@"ViewBridge"] ||
        [bundleID containsString:@"com.apple.appkit.xpc"] ||
        [bundleID containsString:@"Extension"] ||
        [bundleID containsString:@".extension"] ||
        [procName containsString:@"Extension"] ||
        [procName containsString:@"Preference"] ||
        [procName isEqualToString:@"systemsettingsagent"] ||
        [procName containsString:@"ViewService"]) {
      isExt = YES;
    }
  });
  return isExt;
}

/**
 * Returns YES if the current process is specifically a System Settings
 * extension (for finer-grained logic if needed).
 */
static inline BOOL sharpener_is_settings_extension(void) {
  static BOOL isSetExt = NO;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *procName = [[NSProcessInfo processInfo] processName];
    NSString *execPath = [[NSBundle mainBundle] executablePath];
    if ([bundleID containsString:@"com.apple.Settings.Extension"] ||
        [bundleID containsString:@"com.apple.systempreferences"] ||
        [procName containsString:@"Settings.extension"] ||
        [procName
            isEqualToString:@"com.apple.systempreferences.GeneralSettings"] ||
        [bundleID containsString:@".Settings.extension"] ||
        [procName isEqualToString:@"General"] ||
        [procName isEqualToString:@"Desktop"] ||
        [procName isEqualToString:@"ScreenSaver"] ||
        [procName isEqualToString:@"Wallpaper"] ||
        [execPath containsString:@"System Settings.app"] ||
        [execPath containsString:@"SystemPreferences"]) {
      isSetExt = YES;
    }
  });
  return isSetExt;
}

/**
 * Returns YES if the current process is a Chromium-based browser or Electron
 * app. These apps are extremely sensitive to CALayer modifications on their
 * root views.
 */
static inline BOOL sharpener_is_chromium_based_process(void) {
  static BOOL isChromium = NO;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *procName = [[NSProcessInfo processInfo] processName];

    // Common Chromium-based browser bundle IDs
    if ([bundleID isEqualToString:@"com.google.Chrome"] ||
        [bundleID isEqualToString:@"com.brave.Browser"] ||
        [bundleID isEqualToString:@"com.microsoft.edgemac"] ||
        [bundleID isEqualToString:@"com.vivaldi.Vivaldi"] ||
        [bundleID isEqualToString:@"com.operasoftware.Opera"]) {
      isChromium = YES;
      return;
    }

    // Common Electron/Chromium Process Names or patterns
    if ([procName containsString:@"Chrome"] ||
        [procName containsString:@"Chromium"] ||
        [procName containsString:@"Brave"] ||
        [procName containsString:@"Electron"] ||
        [procName containsString:@"Visual Studio Code"] ||
        [procName containsString:@"Discord"] ||
        [procName containsString:@"Slack"]) {
      isChromium = YES;
      return;
    }

    // Deep check for Electron/Chromium Frameworks in loaded images
    // This catches apps like Spotify, Teams, etc. that rename their
    // executables.
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
      const char *name = _dyld_get_image_name(i);
      if (name && (strstr(name, "Electron Framework") ||
                   strstr(name, "Chromium Framework"))) {
        isChromium = YES;
        break;
      }
    }
  });
  return isChromium;
}

/**
 * Returns YES if the current process is a Chromium or Electron HELPER
 * (Renderer, GPU, Utility, Crashpad, etc.). These processes must NOT
 * be modified or even have swizzles installed, as they trigger SIGTRAP
 * due to hardening.
 */
static inline BOOL sharpener_is_chromium_helper_process(void) {
  static BOOL isHelper = NO;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *procName = [[NSProcessInfo processInfo] processName];

    // Detect by bundle ID pattern (e.g., com.brave.Browser.helper.renderer)
    if ([bundleID containsString:@".helper"] ||
        [bundleID containsString:@"crashpad_handler"]) {
      isHelper = YES;
      return;
    }

    // Detect by process name pattern
    if ([procName containsString:@" Helper"] ||
        [procName containsString:@"Crashpad"] ||
        [procName isEqualToString:@"chrome_crashpad_handler"] ||
        [procName containsString:@"(Renderer)"] ||
        [procName containsString:@"(GPU)"]) {
      isHelper = YES;
      return;
    }
  });
  return isHelper;
}

/**
 * Returns YES only when this process executable lives under
 * `Something.app/Contents/MacOS/...` (normal GUI apps, Dock, menu bar apps).
 *
 * Returns NO for compilers, CLI tools, scripting runtimes, and for
 * `.appex`, `.xpc`, and `XPCServices` bundles even though some link AppKit.
 */
static inline BOOL sharpener_should_install_dyld_hook(void) {
  char path[4096];
  uint32_t size = (uint32_t)sizeof(path);
  if (_NSGetExecutablePath(path, &size) != 0)
    return NO;

  if (strstr(path, ".appex/") || strstr(path, "/XPCServices/") ||
      strstr(path, ".xpc/Contents/MacOS")) {
    return NO;
  }

  return strstr(path, ".app/Contents/MacOS/") != NULL;
}

#endif /* SHARPENER_PROC_UTILS_H */
