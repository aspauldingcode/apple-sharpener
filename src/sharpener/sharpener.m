#import "Dock/dock.h"
#import "Windows/window.h"
#import "proc_utils.h"
#import "sharpener_log.h"
#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

/**
 * Main sharpener coordinator
 * This file serves as the entry point and coordinates the Windows and Dock
 * modules.
 *
 * FILTERING STRATEGY (layers):
 *
 * Layer 1 — Ammonia blacklist (libapple_sharpener.dylib.blacklist):
 *   Prevents injection into known system daemons at the loader level.
 *
 * Layer 2 — GUI executable guard (proc_utils.h sharpener_should_install_dyld_hook):
 *   Skip registering the AppKit image callback for CLI tools, compilers, and
 *   background binaries that are not launched from an app bundle MacOS folder
 *   (and exclude XPC bundles and appex). Avoids Swift/clang/launchd-style tools.
 *
 * Layer 3 — Extension process guard:
 *   Skips System Settings XPC / ViewBridge hosts, etc.
 *
 * Layer 4 — dyld AppKit image callback (this file):
 *   Initializes only after AppKit.framework loads, on the main queue (after
 *   +load). Processes that never load AppKit stay dormant.
 *
 * The Dock is initialized via `setupDockNotifications()` in this callback;
 * other apps use `initWindowSharpener()`.
 */

#pragma mark - AppKit Detection via dyld Image Handler

static BOOL appkitDetected = NO;

static void onImageLoaded(const struct mach_header *mh, intptr_t slide) {
  (void)slide;
  if (appkitDetected)
    return;

  Dl_info info;
  if (dladdr(mh, &info) && info.dli_fname) {
    if (strstr(info.dli_fname, "AppKit.framework") == NULL)
      return;

    appkitDetected = YES;

    if (sharpener_is_extension_process()) {
      SHARPENER_LOG(@"Skipping init — extension/helper process");
      return;
    }

    SHARPENER_LOG(@"AppKit loaded — scheduling sharpener init");
    dispatch_async(dispatch_get_main_queue(), ^{
      if (isDockProcess()) {
        SHARPENER_LOG(@"init dock hooks");
        setupDockNotifications();
      } else {
        SHARPENER_LOG(@"initWindowSharpener");
        initWindowSharpener();
      }
      SHARPENER_LOG(@"sharpener init finished");
    });
  }
}

/**
 * Registers the dyld image handler for GUI app bundles only.
 * No stderr/stdout logging here — file log only when APPLE_SHARPENER_LOGS.
 */
__attribute__((constructor)) static void sharpener_appkit_guard(void) {
  if (!sharpener_should_install_dyld_hook())
    return;

  if (sharpener_is_extension_process())
    return;

  _dyld_register_func_for_add_image(onImageLoaded);
}

// Implementations: Windows/window.m, Dock/dock.m
