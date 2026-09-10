/**
 * Apple Sharpener: Dock Sharpening Implementation
 *
 * Implements the logic to find the Dock bar's backdrop layer and apply
 * custom corner radii and borders. It uses a method swizzle on 
 * CALayer's layoutSublayers to detect the Dock bar dynamically.
 */

#import "dock.h"
#import "sharpener_log.h"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <objc/runtime.h>

NSString *const kDockBundleIdentifier = @"com.apple.dock";

/// Dock layer is only stable up to this radius; global/windows may go to 100.
static const NSInteger kSharpenerDockRadiusMaximum = 46;

static BOOL enableDockSharpener = YES;
static NSInteger dockCustomRadius = 0;
static BOOL dockBordersEnabled = NO;
static CGFloat dockBorderWidth = 1.0;
/// ARGB string applied when borders are on (includes fallback color).
static NSString *dockBorderHexPaint = nil;

BOOL isDockProcess(void) {
  return [[[NSBundle mainBundle] bundleIdentifier]
      isEqualToString:kDockBundleIdentifier];
}

static BOOL isDockBarLayer(CALayer *layer) {
  for (CALayer *p = layer.superlayer; p; p = p.superlayer) {
    if ([[p className] containsString:@"ModernFloorLayer"])
      return YES;
  }
  return NO;
}

static CGColorRef ASHexARGBToCGColor(NSString *hex) {
  if (!hex.length)
    return NULL;
  NSString *s = hex;
  if ([s hasPrefix:@"0x"] || [s hasPrefix:@"0X"])
    s = [s substringFromIndex:2];
  if (s.length != 8)
    return NULL;
  unsigned v = 0;
  if (![[NSScanner scannerWithString:s] scanHexInt:&v])
    return NULL;
  CGFloat a = ((v >> 24) & 0xFF) / 255.0;
  CGFloat r = ((v >> 16) & 0xFF) / 255.0;
  CGFloat g = ((v >> 8) & 0xFF) / 255.0;
  CGFloat b = (v & 0xFF) / 255.0;
  return [NSColor colorWithDeviceRed:r green:g blue:b alpha:a].CGColor;
}

static void ASStyleDockBackdrop(CALayer *layer) {
  layer.cornerRadius = dockCustomRadius;
  layer.masksToBounds = YES;
  if (dockBordersEnabled && dockBorderHexPaint.length) {
    layer.borderWidth = dockBorderWidth;
    layer.borderColor = ASHexARGBToCGColor(dockBorderHexPaint);
  } else {
    layer.borderWidth = 0;
    layer.borderColor = NULL;
  }
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  [layer setNeedsDisplay];
  [layer displayIfNeeded];
  id c = layer.contents;
  layer.contents = nil;
  layer.contents = c;
  [CATransaction commit];
}

/// Undo dock bar tweaks so Dock can fall back to system drawing (module off).
static void ASRestoreDefaultDockBackdrop(CALayer *layer) {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  layer.cornerRadius = 0;
  layer.masksToBounds = NO;
  layer.borderWidth = 0;
  layer.borderColor = NULL;
  [layer setNeedsDisplay];
  [layer displayIfNeeded];
  id c = layer.contents;
  layer.contents = nil;
  layer.contents = c;
  [CATransaction commit];
}

static IMP __LayoutSublayers = NULL;

static void _PatchedLayoutSublayers(id self, SEL _cmd) {
  if (__LayoutSublayers)
    ((void (*)(id, SEL))__LayoutSublayers)(self, _cmd);
  if (!isDockProcess() || !enableDockSharpener)
    return;

  CALayer *layer = (CALayer *)self;
  NSString *cn = [layer className];
  if ([cn containsString:@"Label"] || [cn containsString:@"TileLabel"] ||
      [cn containsString:@"Text"] || [cn containsString:@"Icon"] ||
      [cn containsString:@"Tile"] || [cn containsString:@"Item"] ||
      [cn containsString:@"Trash"] || [cn containsString:@"Badge"] ||
      [cn containsString:@"Indicator"])
    return;
  if (![cn isEqualToString:@"CASDFElementLayer"])
    return;

  for (CALayer *p = layer.superlayer; p; p = p.superlayer) {
    NSString *pc = [p className];
    if ([pc containsString:@"Label"] || [pc containsString:@"Tile"] ||
        [pc containsString:@"Icon"] || [pc containsString:@"Item"] ||
        [pc containsString:@"Trash"] || [pc containsString:@"Badge"] ||
        [pc containsString:@"Indicator"])
      return;
  }
  if (!isDockBarLayer(layer))
    return;
  ASStyleDockBackdrop(layer);
}

static void ASWalkDockLayersApplyOrRestore(CALayer *root, BOOL sharpeningOn) {
  NSMutableArray<CALayer *> *q = [NSMutableArray arrayWithObject:root];
  while (q.count) {
    CALayer *ly = q.firstObject;
    [q removeObjectAtIndex:0];
    [ly setNeedsLayout];
    [ly layoutIfNeeded];
    if ([[ly className] isEqualToString:@"CASDFElementLayer"] &&
        isDockBarLayer(ly)) {
      if (sharpeningOn) {
        // Clear stale state, then re-apply persisted radius/borders (menubar
        // toggle / modules.update parity with window module).
        ASRestoreDefaultDockBackdrop(ly);
        ASStyleDockBackdrop(ly);
      } else {
        ASRestoreDefaultDockBackdrop(ly);
      }
    }
    for (CALayer *sl in ly.sublayers)
      [q addObject:sl];
  }
}

void toggleDockCorners(BOOL enable, NSInteger radius) {
  if (!isDockProcess())
    return;
  enableDockSharpener = enable;
  dockCustomRadius = MAX(0, radius);
  @try {
    for (NSWindow *w in NSApplication.sharedApplication.windows) {
      CALayer *root = w.contentView.layer;
      if (!root)
        continue;
      ASWalkDockLayersApplyOrRestore(root, enable);
      [w invalidateShadow];
      [w displayIfNeeded];
    }
  } @catch (__unused NSException *e) {
  }
}

static id ASGetDockPref(NSString *suffix) {
  if (!suffix) return nil;
  NSString *key = [NSString stringWithFormat:@"AppleSharpener_%@", suffix];
  
  // 1. Check Global Domain (prefixed)
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

static void refreshDockSettings(void) {
  id gEn = ASGetDockPref(@"enabled");
  BOOL masterEnabled = (gEn == nil) || [gEn boolValue];

  id dockEn = ASGetDockPref(@"dock_enabled");
  if (dockEn != nil) {
    enableDockSharpener = masterEnabled && [dockEn boolValue];
  } else {
    enableDockSharpener = masterEnabled;
  }
  
  NSLog(@"[AppleSharpener] refreshDockSettings: master=%d, dock=%d", masterEnabled, enableDockSharpener);

  if (!enableDockSharpener) {
    // Module off: never inherit global radius/borders — that re-applied global
    // sharpening and looked like "dock still follows global."
    id dr = ASGetDockPref(@"dock_radius");
    dockCustomRadius = dr ? [dr integerValue] : 0;
    dockBordersEnabled = NO;
    dockBorderWidth = 1.0;
    dockBorderHexPaint = nil;
    return;
  }

  id dockRadVal = ASGetDockPref(@"dock_radius");
  id globalRadVal = ASGetDockPref(@"radius");
  if (dockRadVal != nil) {
    NSInteger r = MAX(0, [dockRadVal integerValue]);
    dockCustomRadius = MIN(r, kSharpenerDockRadiusMaximum);
  } else if (globalRadVal != nil) {
    NSInteger g = MAX(0, [globalRadVal integerValue]);
    dockCustomRadius = MIN(g, kSharpenerDockRadiusMaximum);
  }

  id val;
  id (^ASResolve)(NSString *, NSString *) = ^id(NSString *mod, NSString *glob) {
    id v = ASGetDockPref(mod);
    if (v) return v;
    return ASGetDockPref(glob);
  };

  if ((val = ASResolve(@"dock_borders", @"global_borders")))
    dockBordersEnabled = [val boolValue];
  if ((val = ASResolve(@"dock_border_width", @"global_border_width")))
    dockBorderWidth = [val doubleValue];

  NSString *hex = nil;
  if ((val = ASResolve(@"dock_border_color_active", @"global_border_color_active")))
    hex = [val isKindOfClass:[NSString class]] ? val : nil;
  if (dockBordersEnabled && !hex.length)
    hex = @"0xFF808080";
  dockBorderHexPaint = hex.length ? hex : nil;
}

static void dockOnSettingsChanged(__unused int tok) {
  refreshDockSettings();
  toggleDockCorners(enableDockSharpener, dockCustomRadius);
}

void setupDockNotifications(void) {
  if (!isDockProcess())
    return;
  SHARPENER_LOG(@"Dock hooks: %@", NSBundle.mainBundle.bundleIdentifier);

  Method m = class_getInstanceMethod([CALayer class], @selector(layoutSublayers));
  if (m) {
    __LayoutSublayers = method_getImplementation(m);
    method_setImplementation(m, (IMP)_PatchedLayoutSublayers);
  }

  const char *names[] = {
      "com.aspauldingcode.apple_sharpener.dock.set_radius",
      "com.aspauldingcode.apple_sharpener.modules.update",
      "com.aspauldingcode.apple_sharpener.dock.enabled",
  };
  for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
    int token = 0;
    notify_register_dispatch(names[i], &token, dispatch_get_main_queue(),
                             ^(int __unused t) { dockOnSettingsChanged(0); });
  }

  refreshDockSettings();
  toggleDockCorners(enableDockSharpener, dockCustomRadius);

  [NSDistributedNotificationCenter.defaultCenter
      addObserverForName:@"com.aspauldingcode.apple_sharpener.modules.update"
                  object:nil
                   queue:NSOperationQueue.mainQueue
              usingBlock:^(__unused NSNotification *n) {
                dockOnSettingsChanged(0);
              }];
}
