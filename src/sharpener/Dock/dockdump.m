/**
 * Apple Sharpener: Dock Layer Dumper
 *
 * A utility to dump the Dock's view and layer hierarchy for debugging 
 * purposes. Used via `make dumpdock`.
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <errno.h>
#import <objc/runtime.h>
#import <unistd.h>

/**
 * Dock layer dumper - injects into dock and logs all CALayer class names
 * This helps identify which layer is the dock background
 */

static void setupDumpFile(void) {}

static void logLayer(CALayer *layer, int depth) {
  if (!layer)
    return;

  NSString *className = [layer className];
  CGRect bounds = layer.bounds;
  CALayer *superlayer = layer.superlayer;
  NSString *superClassName = superlayer ? [superlayer className] : @"(root)";

  // Log to stdout
  for (int i = 0; i < depth; i++) {
    printf("  ");
  }
  printf("%s\n", [className UTF8String]);
  printf("%*s  Bounds: %.1f x %.1f\n", depth * 2, "", bounds.size.width,
         bounds.size.height);
  printf("%*s  Superlayer: %s\n", depth * 2, "", [superClassName UTF8String]);
  printf("%*s  CornerRadius: %.1f\n", depth * 2, "", layer.cornerRadius);
  printf("%*s  MasksToBounds: %s\n", depth * 2, "",
         layer.masksToBounds ? "YES" : "NO");
  printf("%*s  BackgroundColor: %s\n", depth * 2, "",
         layer.backgroundColor ? "set" : "nil");
  printf("\n");
  fflush(stdout);

  // Only log to file, not to NSLog to avoid console spam

  // Recursively log sublayers
  if (layer.sublayers) {
    for (CALayer *sublayer in layer.sublayers) {
      logLayer(sublayer, depth + 1);
    }
  }
}

// Store original method implementation
static IMP __LayoutSublayers = NULL;

// Hooked layoutSublayers method
static void _PatchedLayoutSublayers(id self, SEL _cmd) {
  // Call original implementation first
  if (__LayoutSublayers) {
    ((void (*)(id, SEL))__LayoutSublayers)(self, _cmd);
  }

  // Only dump if we're in the dock process
  NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
  if (![bundleId isEqualToString:@"com.apple.dock"]) {
    return;
  }

  CALayer *layer = (CALayer *)self;
  NSString *className = [layer className];

  // Only log dock-related layers to avoid spam
  if ([className containsString:@"Dock"] ||
      [className containsString:@"Background"] ||
      [className containsString:@"Floor"] || layer.superlayer == nil) {

    // Log the layer hierarchy
    if (layer.superlayer == nil || [className containsString:@"Dock"]) {
      logLayer(layer, 0);
    }
  }
}

static void setupDockDump(void) __attribute__((constructor));
static void setupDockDump(void) {
  NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];

  // Silently skip if not in Dock process - don't log to avoid console spam
  if (![bundleId isEqualToString:@"com.apple.dock"]) {
    return;
  }

  setupDumpFile();

  // Hook CALayer's layoutSublayers method
  Class layerClass = [CALayer class];
  Method originalMethod =
      class_getInstanceMethod(layerClass, @selector(layoutSublayers));
  if (originalMethod) {
    __LayoutSublayers = method_getImplementation(originalMethod);
    method_setImplementation(originalMethod, (IMP)_PatchedLayoutSublayers);
  }

  // Also try to dump window layers immediately
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        @try {
          NSApplication *app = [NSApplication sharedApplication];
          if (app) {
            for (NSWindow *window in app.windows) {
              if (window.contentView && window.contentView.layer) {
                logLayer(window.contentView.layer, 0);
              }
            }
          }
        } @catch (NSException *exception) {
          // Silently ignore exceptions
        }
      });
}
