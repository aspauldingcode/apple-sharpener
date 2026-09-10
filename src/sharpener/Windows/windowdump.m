/**
 * Apple Sharpener: Window Layer Dumper
 *
 * A utility to dump the view and layer hierarchy of the current application
 * to a file for debugging purposes. Used via `make dumpwindow`.
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <errno.h>
#import <objc/runtime.h>
#import <unistd.h>

/**
 * Generic window view layout dumper - injects into any app and logs:
 * - All CALayer class names and hierarchy
 * - NSWindow/NSView hierarchy
 * - Class dumps of relevant classes
 * This helps identify which layers/windows need corner radius modification
 *
 * Usage: Build with -DAPP_IDENTIFIER="app_name_or_bundle_id" to target a
 * specific app
 */

#define dumpFile stdout
static NSString *targetAppIdentifier = nil;

static void setupDumpFile(void) {}

static void logLayer(CALayer *layer, int depth) {
  if (!layer)
    return;

  NSString *className = [layer className];
  CGRect bounds = layer.bounds;
  CALayer *superlayer = layer.superlayer;
  NSString *superClassName = superlayer ? [superlayer className] : @"(root)";

  // Log to file
  if (dumpFile) {
    for (int i = 0; i < depth; i++) {
      fprintf(dumpFile, "  ");
    }
    fprintf(dumpFile, "CALayer: %s\n", [className UTF8String]);
    fprintf(dumpFile, "%*s  Bounds: %.1f x %.1f at (%.1f, %.1f)\n", depth * 2,
            "", bounds.size.width, bounds.size.height, bounds.origin.x,
            bounds.origin.y);
    fprintf(dumpFile, "%*s  Superlayer: %s\n", depth * 2, "",
            [superClassName UTF8String]);
    fprintf(dumpFile, "%*s  CornerRadius: %.1f\n", depth * 2, "",
            layer.cornerRadius);
    fprintf(dumpFile, "%*s  MasksToBounds: %s\n", depth * 2, "",
            layer.masksToBounds ? "YES" : "NO");
    fprintf(dumpFile, "%*s  BackgroundColor: %s\n", depth * 2, "",
            layer.backgroundColor ? "set" : "nil");
    fprintf(dumpFile, "%*s  Hidden: %s\n", depth * 2, "",
            layer.hidden ? "YES" : "NO");
    fprintf(dumpFile, "%*s  Opacity: %.2f\n", depth * 2, "", layer.opacity);
    fprintf(dumpFile, "\n");
    fflush(dumpFile);
  }

  // Recursively log sublayers
  if (layer.sublayers) {
    for (CALayer *sublayer in layer.sublayers) {
      logLayer(sublayer, depth + 1);
    }
  }
}

static void logView(NSView *view, int depth) {
  if (!view)
    return;

  NSString *className = [view className];
  NSRect frame = view.frame;
  NSView *superview = view.superview;
  NSString *superClassName = superview ? [superview className] : @"(root)";

  // Log to file
  if (dumpFile) {
    for (int i = 0; i < depth; i++) {
      fprintf(dumpFile, "  ");
    }
    fprintf(dumpFile, "NSView: %s\n", [className UTF8String]);
    fprintf(dumpFile, "%*s  Frame: %.1f x %.1f at (%.1f, %.1f)\n", depth * 2,
            "", frame.size.width, frame.size.height, frame.origin.x,
            frame.origin.y);
    fprintf(dumpFile, "%*s  Superview: %s\n", depth * 2, "",
            [superClassName UTF8String]);
    fprintf(dumpFile, "%*s  Hidden: %s\n", depth * 2, "",
            view.hidden ? "YES" : "NO");
    fprintf(dumpFile, "%*s  WantsLayer: %s\n", depth * 2, "",
            view.wantsLayer ? "YES" : "NO");
    if (view.layer) {
      fprintf(dumpFile, "%*s  Layer: %s\n", depth * 2, "",
              [[view.layer className] UTF8String]);
    }
    fprintf(dumpFile, "\n");
    fflush(dumpFile);
  }

  // Recursively log subviews
  for (NSView *subview in view.subviews) {
    logView(subview, depth + 1);
  }
}

static void logWindow(NSWindow *window) {
  if (!window || !dumpFile)
    return;

  NSString *className = [window className];
  NSRect frame = window.frame;
  NSWindowStyleMask styleMask = window.styleMask;

  fprintf(dumpFile, "=== NSWindow ===\n");
  fprintf(dumpFile, "Class: %s\n", [className UTF8String]);
  fprintf(dumpFile, "Frame: %.1f x %.1f at (%.1f, %.1f)\n", frame.size.width,
          frame.size.height, frame.origin.x, frame.origin.y);
  fprintf(dumpFile, "StyleMask: 0x%lx\n", (unsigned long)styleMask);
  fprintf(dumpFile, "Level: %ld\n", (long)window.level);
  fprintf(dumpFile, "Visible: %s\n", window.isVisible ? "YES" : "NO");
  fprintf(dumpFile, "Title: %s\n", [window.title UTF8String]);

  // Check if it's an NSPanel
  Class panelClass = NSClassFromString(@"NSPanel");
  if (panelClass && [window isKindOfClass:panelClass]) {
    fprintf(dumpFile, "Type: NSPanel\n");
  } else {
    fprintf(dumpFile, "Type: NSWindow\n");
  }

  fprintf(dumpFile, "\n");

  // Log content view hierarchy
  if (window.contentView) {
    fprintf(dumpFile, "=== Content View Hierarchy ===\n");
    logView(window.contentView, 0);
  }

  // Log layer hierarchy
  if (window.contentView && window.contentView.layer) {
    fprintf(dumpFile, "=== Content View Layer Hierarchy ===\n");
    logLayer(window.contentView.layer, 0);
  }

  fprintf(dumpFile, "\n");
  fflush(dumpFile);
}

static void dumpClassInfo(Class cls, const char *className) {
  if (!cls || !dumpFile)
    return;

  fprintf(dumpFile, "=== Class Info: %s ===\n", className);

  unsigned int methodCount = 0;
  Method *methods = class_copyMethodList(cls, &methodCount);
  if (methods) {
    fprintf(dumpFile, "Methods (%u):\n", methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
      SEL selector = method_getName(methods[i]);
      const char *methodName = sel_getName(selector);
      fprintf(dumpFile, "  - %s\n", methodName);
    }
    free(methods);
  }

  unsigned int propCount = 0;
  objc_property_t *properties = class_copyPropertyList(cls, &propCount);
  if (properties) {
    fprintf(dumpFile, "Properties (%u):\n", propCount);
    for (unsigned int i = 0; i < propCount; i++) {
      const char *propName = property_getName(properties[i]);
      fprintf(dumpFile, "  @property %s\n", propName);
    }
    free(properties);
  }

  fprintf(dumpFile, "\n");
  fflush(dumpFile);
}

// Check if current process matches target app identifier
static BOOL matchesTargetApp(void) {
  if (!targetAppIdentifier || targetAppIdentifier.length == 0) {
    return YES; // No target specified, match all apps
  }

  NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
  NSString *processName = [[NSProcessInfo processInfo] processName];

  NSString *lowerTarget = targetAppIdentifier.lowercaseString;

  // Check bundle ID
  if (bundleId) {
    NSString *lowerBundleId = bundleId.lowercaseString;
    if ([lowerBundleId isEqualToString:lowerTarget] ||
        [lowerBundleId containsString:lowerTarget] ||
        [lowerTarget containsString:lowerBundleId]) {
      return YES;
    }
  }

  // Check process name
  if (processName) {
    NSString *lowerProcessName = processName.lowercaseString;
    if ([lowerProcessName isEqualToString:lowerTarget] ||
        [lowerProcessName containsString:lowerTarget] ||
        [lowerTarget containsString:lowerProcessName]) {
      return YES;
    }
  }

  return NO;
}

// Store original method implementation
static IMP __LayoutSublayers = NULL;

// Hooked layoutSublayers method
static void _PatchedLayoutSublayers(id self, SEL _cmd) {
  // Call original implementation first
  if (__LayoutSublayers) {
    ((void (*)(id, SEL))__LayoutSublayers)(self, _cmd);
  }

  // Only dump if we match target app
  if (!matchesTargetApp()) {
    return;
  }

  CALayer *layer = (CALayer *)self;

  // Log interesting layers (root layers or those with corner radius)
  if (layer.superlayer == nil || layer.cornerRadius > 0) {
    logLayer(layer, 0);
  }
}

static void setupWindowDump(void) __attribute__((constructor));
static void setupWindowDump(void) {
  // Get target app identifier from compile-time define
#ifdef APP_IDENTIFIER
  targetAppIdentifier = [NSString stringWithUTF8String:APP_IDENTIFIER];
#endif

  // Check if we should run in this process
  if (!matchesTargetApp()) {
    return;
  }

  NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
  NSString *processName = [[NSProcessInfo processInfo] processName];

  setupDumpFile();

  if (dumpFile) {
    fprintf(dumpFile, "=== Process Info ===\n");
    fprintf(dumpFile, "Target Identifier: %s\n",
            targetAppIdentifier ? [targetAppIdentifier UTF8String] : "(any)");
    fprintf(dumpFile, "Bundle ID: %s\n",
            bundleId ? [bundleId UTF8String] : "(nil)");
    fprintf(dumpFile, "Process Name: %s\n",
            processName ? [processName UTF8String] : "(nil)");
    fprintf(dumpFile, "Dump initialized successfully!\n");
    fprintf(dumpFile, "\n");
    fflush(dumpFile);
  }

  // Hook CALayer's layoutSublayers method
  Class layerClass = NSClassFromString(@"CALayer");
  if (layerClass) {
    Method originalMethod =
        class_getInstanceMethod(layerClass, @selector(layoutSublayers));
    if (originalMethod) {
      __LayoutSublayers = method_getImplementation(originalMethod);
      method_setImplementation(originalMethod, (IMP)_PatchedLayoutSublayers);
    }
  }

  // Dump class information for interesting classes
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        @try {
          // Dump NSApplication and its actual class
          NSApplication *app = [NSApplication sharedApplication];
          if (app) {
            if (dumpFile) {
              fprintf(dumpFile, "=== NSApplication Info ===\n");
              fprintf(dumpFile, "Class: %s\n",
                      [NSStringFromClass([app class]) UTF8String]);
              fprintf(dumpFile, "Superclass: %s\n",
                      [NSStringFromClass([app superclass]) UTF8String]);
              fprintf(dumpFile, "Windows Count: %lu\n\n",
                      (unsigned long)app.windows.count);
              fflush(dumpFile);

              // Dump all methods of the actual application class
              Class appClass = [app class];
              if (appClass && appClass != [NSApplication class]) {
                dumpClassInfo(appClass,
                              [NSStringFromClass(appClass) UTF8String]);
              }
            }

            // Dump all windows
            for (NSWindow *window in app.windows) {
              logWindow(window);
            }
          }

          // Periodically dump windows (every 3 seconds for 30 seconds)
          static int dumpCount = 0;
          static void (^scheduleNextDump)(void);
          scheduleNextDump = ^{
            @try {
              NSApplication *app = [NSApplication sharedApplication];
              if (app && dumpFile && dumpCount < 10) {
                fprintf(dumpFile, "=== Periodic Window Dump #%d (at %s) ===\n",
                        dumpCount + 1,
                        [[[NSDate date] description] UTF8String]);
                fprintf(dumpFile, "Total windows: %lu\n",
                        (unsigned long)app.windows.count);
                fflush(dumpFile);
                for (NSWindow *window in app.windows) {
                  logWindow(window);
                }
                dumpCount++;
                // Schedule next dump
                if (dumpCount < 10) {
                  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                               (int64_t)(3.0 * NSEC_PER_SEC)),
                                 dispatch_get_main_queue(), scheduleNextDump);
                } else {
                  if (dumpFile) {
                    fprintf(dumpFile, "\n=== Dump Complete ===\n");
                    fflush(dumpFile);
                  }
                }
              }
            } @catch (NSException *exception) {
              // Silently ignore
            }
          };
          dispatch_after(
              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
              dispatch_get_main_queue(), scheduleNextDump);
        } @catch (NSException *exception) {
          // Silently ignore exceptions
        }
      });
}
