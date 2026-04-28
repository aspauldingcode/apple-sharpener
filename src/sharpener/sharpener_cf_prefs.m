#import "sharpener_cf_prefs.h"
#import <CoreFoundation/CoreFoundation.h>

static NSSet *SharpenerMirroredSuiteKeys(void) {
  static NSSet *keys;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    keys = [NSSet setWithObjects:
        @"enabled", @"radius", @"squircle_enabled", @"squircle_exponent",
        @"global_borders", @"global_border_width", @"global_border_color_active",
        @"global_border_color_inactive", @"global_shadows", @"windows_enabled",
        @"windows_radius", @"windows_squircle", @"windows_squircle_exponent",
        @"windows_shadows", @"windows_borders", @"windows_border_width",
        @"windows_border_color_active", @"windows_border_color_inactive",
        @"traffic_lights_mode", @"sidebar_mode", @"toolbar_mode", @"dock_enabled",
        @"dock_radius", @"dock_squircle", @"dock_squircle_exponent",
        @"dock_borders", @"dock_border_width", @"dock_border_color_active",
        @"dock_border_color_inactive", @"rules", nil];
  });
  return keys;
}

void SharpenerMirrorSuiteDefaultsToCF(NSUserDefaults *suite) {
  if (!suite)
    return;
  [suite synchronize];
  NSDictionary *d = suite.dictionaryRepresentation;
  NSSet *allowed = SharpenerMirroredSuiteKeys();

  for (NSString *key in d) {
    if (![allowed containsObject:key])
      continue;
    id v = d[key];
    if (!v || v == (id)kCFNull)
      continue;
    if (![v isKindOfClass:[NSString class]] && ![v isKindOfClass:[NSNumber class]] &&
        ![v isKindOfClass:[NSData class]] && ![v isKindOfClass:[NSArray class]] &&
        ![v isKindOfClass:[NSDictionary class]] && ![v isKindOfClass:[NSDate class]])
      continue;

    NSString *cfKey = [NSString stringWithFormat:@"AppleSharpener_%@", key];
    CFPreferencesSetValue((__bridge CFStringRef)cfKey,
                          (__bridge CFPropertyListRef)v,
                          kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
  }
  CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                           kCFPreferencesAnyHost);
}

void SharpenerPostModulesUpdateNotification(void) {
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:@"com.aspauldingcode.apple_sharpener.modules.update"
                    object:nil
                  userInfo:nil
       deliverImmediately:YES];
}
