/**
 * Apple Sharpener: Background Helper Daemon
 *
 * This daemon watches the ~/.config/sharpener/config.kdl file and 
 * synchronizes its contents with the NSUserDefaults suite and global 
 * CFPreferences. It also broadcasts system-wide notifications when 
 * settings change.
 */

#import <Foundation/Foundation.h>
#import "sharpener_log.h"
#import <notify.h>
#include <sys/event.h>
#import <sys/stat.h>
#include <sys/time.h>

// Match `clitool.m` / ASConfigurator `SharpenerConfig.RadiusLimit`.
static inline NSInteger ASClampRadiusWindows(NSInteger v) {
  if (v < 0)
    return 0;
  if (v > 100)
    return 100;
  return v;
}

static inline NSInteger ASClampRadiusDock(NSInteger v) {
  if (v < 0)
    return 0;
  if (v > 46)
    return 46;
  return v;
}

@interface ASConfigHelper : NSObject {
  dispatch_source_t _watcher;
}
+ (instancetype)shared;
- (void)loadConfig;
- (void)startWatching;
@end

@implementation ASConfigHelper

+ (instancetype)shared {
  static ASConfigHelper *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[self alloc] init];
  });
  return shared;
}

- (NSString *)configPath {
  return [[NSHomeDirectory()
      stringByAppendingPathComponent:@".config/sharpener/config.kdl"]
      stringByStandardizingPath];
}

- (void)loadConfig {
  NSString *path = [self configPath];
  SHARPENER_LOG(@"[sharpener-helper] Loading config from: %@", path);

  NSError *error = nil;
  NSString *content = [NSString stringWithContentsOfFile:path
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
  if (!content) {
    SHARPENER_LOG(@"[sharpener-helper] Config file not found at %@", path);
    return;
  }

  NSUserDefaults *defaults = [[NSUserDefaults alloc]
      initWithSuiteName:@"com.aspauldingcode.apple_sharpener.temp"];
  [defaults
      removePersistentDomainForName:@"com.aspauldingcode.apple_sharpener.temp"];
  BOOL needsUpdateWindows = NO;
  BOOL needsUpdateDock = NO;

  // --- Robust KDL Extraction (Manual parsing for userspace dylib) ---

  NSString * (^extractBlock)(NSString *, NSString *) =
      ^NSString *(NSString *blockName, NSString *str) {
        if (!str)
          return nil;
        NSArray<NSString *> *lines = [str componentsSeparatedByString:@"\n"];
        NSInteger depth = 0;
        BOOL inBlock = NO;
        NSMutableString *result = [NSMutableString string];
        for (NSString *rawLine in lines) {
          NSString *line = [rawLine
              stringByTrimmingCharactersInSet:[NSCharacterSet
                                                  whitespaceCharacterSet]];
          if (!inBlock) {
            if ([line hasPrefix:blockName] && [line containsString:@"{"]) {
              inBlock = YES;
              depth = 1;
            }
            continue;
          }
          // Count braces to handle nesting
          for (NSUInteger i = 0; i < line.length; i++) {
            unichar c = [line characterAtIndex:i];
            if (c == '{')
              depth++;
            else if (c == '}') {
              depth--;
              if (depth <= 0)
                break;
            }
          }
          if (depth <= 0)
            break;
          [result appendFormat:@"%@\n", line];
        }
        return result.length > 0 ? result : nil;
      };

  NSString * (^extractVal)(NSString *, NSString *) = ^NSString *(
      NSString *key, NSString *blockStr) {
    if (!blockStr)
      return nil;
    NSArray<NSString *> *lines = [blockStr componentsSeparatedByString:@"\n"];
    for (NSString *rawLine in lines) {
      NSString *line =
          [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet
                                                       whitespaceCharacterSet]];
      if (line.length == 0 || [line hasPrefix:@"//"])
        continue;
      NSArray<NSString *> *tokens = [line componentsSeparatedByString:@" "];
      NSMutableArray<NSString *> *parts = [NSMutableArray array];
      for (NSString *t in tokens) {
        if (t.length > 0)
          [parts addObject:t];
      }
      if (parts.count >= 2 && [parts[0] isEqualToString:key]) {
        NSString *val = parts[1];
        return
            [val stringByTrimmingCharactersInSet:
                     [NSCharacterSet characterSetWithCharactersInString:@"\""]];
      }
    }
    return nil;
  };

  // Extract root 'sharpener' block
  NSString *sharpenerBlock = extractBlock(@"sharpener", content);
  if (!sharpenerBlock) {
    // Fallback: search the whole file if root block not found (legacy)
    sharpenerBlock = content;
  }

  // Read root enabled
  NSString *rootEn = extractVal(@"enabled", sharpenerBlock);
  if (rootEn) {
    [defaults setBool:[rootEn isEqualToString:@"true"] forKey:@"enabled"];
  }

  // 1. Global Block
  NSString *globalBlock = extractBlock(@"global", sharpenerBlock);
  NSInteger gRad = 14;
  BOOL gSq = YES;
  double gExp = 4.0;
  BOOL gSh = YES;

  if (globalBlock) {
    NSString *r = extractVal(@"radius", globalBlock);
    if (r)
      gRad = ASClampRadiusWindows([r integerValue]);
    else
      gRad = ASClampRadiusWindows(gRad);
    NSString *sq = extractVal(@"squircle", globalBlock);
    if (sq)
      gSq = [sq isEqualToString:@"true"];
    NSString *sqe = extractVal(@"squircle_exponent", globalBlock);
    if (sqe)
      gExp = [sqe doubleValue];
    NSString *sh = extractVal(@"shadows", globalBlock);
    if (sh)
      gSh = [sh isEqualToString:@"true"];

    [defaults setInteger:gRad forKey:@"global_radius"];
    [defaults setBool:gSq forKey:@"global_squircle"];
    [defaults setDouble:gExp forKey:@"global_squircle_exponent"];
    [defaults setBool:gSh forKey:@"global_shadows"];
    needsUpdateWindows = YES;
  }

  // 2. Windows Block (Unified Inheritance)
  NSString *windowsBlock = extractBlock(@"windows", sharpenerBlock);
  if (windowsBlock) {
    NSString *en = extractVal(@"enabled", windowsBlock);
    [defaults setBool:(en ? [en isEqualToString:@"true"] : YES)
               forKey:@"windows_enabled"];

    NSString *r = extractVal(@"radius", windowsBlock);
    NSInteger winR = r ? ASClampRadiusWindows([r integerValue]) : gRad;
    [defaults setInteger:winR forKey:@"windows_radius"];

    NSString *sq = extractVal(@"squircle", windowsBlock);
    [defaults setBool:(sq ? [sq isEqualToString:@"true"] : gSq)
               forKey:@"windows_squircle"];

    NSString *sh = extractVal(@"shadows", windowsBlock);
    [defaults setBool:(sh ? [sh isEqualToString:@"true"] : gSh)
               forKey:@"windows_shadows"];

    NSString *bo = extractVal(@"borders", windowsBlock);
    if (bo)
      [defaults setBool:[bo isEqualToString:@"true"] forKey:@"windows_borders"];
    NSString *bw = extractVal(@"border_width", windowsBlock);
    if (bw)
      [defaults setDouble:[bw doubleValue] forKey:@"windows_border_width"];

    needsUpdateWindows = YES;

    // Helper to parse a submodule inheriting from global + parents
    void (^parseSubmodule)(NSString *, NSString *) = ^(NSString *name,
                                                       NSString *block) {
      NSString *mBlock = extractBlock(name, block);
      if (mBlock) {
        [defaults setObject:@"square"
                     forKey:[name stringByAppendingString:@"_mode"]];
      } else {
        NSString *mode = extractVal(name, block);
        if (mode) {
          // expecting "square", "default", etc.
          mode = [mode stringByReplacingOccurrencesOfString:@"\""
                                                 withString:@""];
          [defaults setObject:mode
                       forKey:[name stringByAppendingString:@"_mode"]];
        } else {
          [defaults removeObjectForKey:[name stringByAppendingString:@"_mode"]];
        }
      }
    };

    parseSubmodule(@"traffic_lights", windowsBlock);
    parseSubmodule(@"sidebar", windowsBlock);
    parseSubmodule(@"toolbar", windowsBlock);
  }

  // 3. Dock Block
  NSString *dockBlock = extractBlock(@"dock", sharpenerBlock);
  if (dockBlock) {
    NSString *en = extractVal(@"enabled", dockBlock);
    [defaults setBool:(en ? [en isEqualToString:@"true"] : YES)
               forKey:@"dock_enabled"];
    NSString *r = extractVal(@"radius", dockBlock);
    NSInteger dockR =
        r ? ASClampRadiusDock([r integerValue]) : ASClampRadiusDock(MIN(gRad, 46));
    [defaults setInteger:dockR forKey:@"dock_radius"];
    needsUpdateDock = YES;
  }

  // 4. Rules Block
  NSString *rulesBlock = extractBlock(@"rules", sharpenerBlock);
  if (rulesBlock) {
    NSMutableArray *rulesArray = [NSMutableArray array];
    // Regex for: app "id" [enabled=...] { body }
    // Handles properties on the header via the second capture group ([^\{]*)
    NSRegularExpression *appRe = [NSRegularExpression
        regularExpressionWithPattern:
            @"app\\s+\"([^\"]+)\"\\s*([^\\{]*)\\{([^\\}]*)\\}"
                             options:0
                               error:nil];
    NSArray *matches =
        [appRe matchesInString:rulesBlock
                       options:0
                         range:NSMakeRange(0, rulesBlock.length)];
    for (NSTextCheckingResult *match in matches) {
      NSString *bundleId =
          [rulesBlock substringWithRange:[match rangeAtIndex:1]];
      NSString *propsString =
          [rulesBlock substringWithRange:[match rangeAtIndex:2]];
      NSString *appBlock =
          [rulesBlock substringWithRange:[match rangeAtIndex:3]];
      NSMutableDictionary *ruleDict = [NSMutableDictionary dictionary];
      ruleDict[@"bundleId"] = bundleId;

      // check enabled in header props
      if ([propsString containsString:@"enabled=true"]) {
        ruleDict[@"enabled"] = @(YES);
      } else if ([propsString containsString:@"enabled=false"]) {
        ruleDict[@"enabled"] = @(NO);
      } else {
        // check enabled inside block body
        NSString *enBody = extractVal(@"enabled", appBlock);
        if (enBody)
          ruleDict[@"enabled"] = @([enBody isEqualToString:@"true"]);
      }

      NSString *r = extractVal(@"radius", appBlock);
      if (r)
        ruleDict[@"radius"] = @(ASClampRadiusWindows([r integerValue]));
      NSString *sq = extractVal(@"squircle", appBlock);
      if (sq)
        ruleDict[@"squircle"] = @([sq isEqualToString:@"true"]);
      NSString *sh = extractVal(@"shadows", appBlock);
      if (sh)
        ruleDict[@"shadows"] = @([sh isEqualToString:@"true"]);

      NSString *tl = extractVal(@"traffic_lights", appBlock);
      if (tl) {
        tl = [tl stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        ruleDict[@"traffic_lights"] = tl;
      }

      NSString *sb = extractVal(@"sidebar", appBlock);
      if (sb) {
        sb = [sb stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        ruleDict[@"sidebar"] = sb;
      }

      NSString *tb = extractVal(@"toolbar", appBlock);
      if (tb) {
        tb = [tb stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        ruleDict[@"toolbar"] = tb;
      }

      [rulesArray addObject:ruleDict];
    }
    [defaults setObject:rulesArray forKey:@"rules"];
    needsUpdateWindows = YES;
  }

  // Root `sharpener.enabled=false` == CLI `sharpener off`: master must override
  // module keys (dylib consults windows_enabled/dock_enabled first).
  if (rootEn && ![rootEn isEqualToString:@"true"]) {
    notify_post("com.aspauldingcode.apple_sharpener.disable");
  }

  [defaults synchronize];

  // Mirror to Global Domain for Sandboxed Apps (Safari, Chess, Word, etc.)
  NSDictionary *dict = [defaults dictionaryRepresentation];
  for (NSString *key in dict) {
    if ([key isEqualToString:@"enabled"] || [key hasPrefix:@"global_"] ||
        [key hasPrefix:@"windows_"] || [key hasPrefix:@"dock_"] ||
        [key hasPrefix:@"traffic_lights_"] || [key hasPrefix:@"sidebar_"] ||
        [key hasPrefix:@"toolbar_"] || [key isEqualToString:@"rules"] ||
        [key hasPrefix:@"squircle_"]) {
      CFPreferencesSetValue(
          (__bridge CFStringRef)
              [NSString stringWithFormat:@"AppleSharpener_%@", key],
          (__bridge CFPropertyListRef)dict[key], kCFPreferencesAnyApplication,
          kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
  }
  CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

  if (needsUpdateWindows) {
    SHARPENER_LOG(@"[sharpener-helper] Broadcasting window settings");

    // Global and Windows Enabled
    int tEn = 0;
    if (notify_register_check("com.aspauldingcode.apple_sharpener.enabled",
                              &tEn) == NOTIFY_STATUS_OK) {
      notify_set_state(tEn, [defaults boolForKey:@"enabled"] ? 1 : 0);
      notify_post("com.aspauldingcode.apple_sharpener.enabled");
    }

    if (notify_register_check(
            "com.aspauldingcode.apple_sharpener.windows.enabled", &tEn) ==
        NOTIFY_STATUS_OK) {
      notify_set_state(tEn, [defaults boolForKey:@"windows_enabled"] ? 1 : 0);
      notify_post("com.aspauldingcode.apple_sharpener.windows.enabled");
    }

    // Radius and Squircle
    int tRad = 0;
    notify_register_check(
        "com.aspauldingcode.apple_sharpener.windows.set_radius", &tRad);
    notify_set_state(tRad, [defaults integerForKey:@"windows_radius"]);
    notify_post("com.aspauldingcode.apple_sharpener.windows.set_radius");

    int tSq = 0;
    notify_register_check("com.aspauldingcode.apple_sharpener.squircle.enabled",
                          &tSq);
    notify_set_state(tSq, [defaults boolForKey:@"windows_squircle"] ? 1 : 0);
    notify_post("com.aspauldingcode.apple_sharpener.squircle.enabled");

    int tEx = 0;
    notify_register_check(
        "com.aspauldingcode.apple_sharpener.squircle.exponent", &tEx);
    notify_set_state(
        tEx, (uint64_t)([defaults doubleForKey:@"squircle_exponent"] * 100.0));
    notify_post("com.aspauldingcode.apple_sharpener.squircle.exponent");

    // Shadows
    int tSh = 0;
    if (notify_register_check(
            "com.aspauldingcode.apple_sharpener.windows.shadows", &tSh) ==
        NOTIFY_STATUS_OK) {
      notify_set_state(tSh, [defaults boolForKey:@"windows_shadows"] ? 1 : 0);
      notify_post("com.aspauldingcode.apple_sharpener.windows.shadows");
    }

    // Border Width
    int tBW = 0;
    if (notify_register_check(
            "com.aspauldingcode.apple_sharpener.windows.border_width", &tBW) ==
        NOTIFY_STATUS_OK) {
      notify_set_state(
          tBW,
          (uint64_t)([defaults doubleForKey:@"windows_border_width"] * 100.0));
      notify_post("com.aspauldingcode.apple_sharpener.windows.border_width");
    }

    // Broadcast module specific updates (Traffic Lights, Sidebar, Toolbar)
    notify_post("com.aspauldingcode.apple_sharpener.modules.update");
  }

  if (needsUpdateDock) {
    int tDEn = 0;
    notify_register_check("com.aspauldingcode.apple_sharpener.dock.enabled",
                          &tDEn);
    notify_set_state(tDEn, [defaults boolForKey:@"dock_enabled"] ? 1 : 0);
    notify_post("com.aspauldingcode.apple_sharpener.dock.enabled");

    int tDRad = 0;
    notify_register_check("com.aspauldingcode.apple_sharpener.dock.set_radius",
                          &tDRad);
    notify_set_state(tDRad, [defaults integerForKey:@"dock_radius"]);
    notify_post("com.aspauldingcode.apple_sharpener.dock.set_radius");
  }
}

- (void)startWatching {
  NSString *path = [self configPath];
  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int kq = kqueue();
        if (kq == -1)
          return;
        int fd = -1;
        while (1) {
          if (fd == -1) {
            fd = open([path UTF8String], O_RDONLY);
            if (fd < 0) {
              usleep(250000);
              continue;
            }
            struct kevent changes;
            EV_SET(&changes, fd, EVFILT_VNODE, EV_ADD | EV_ENABLE | EV_CLEAR,
                   NOTE_DELETE | NOTE_WRITE | NOTE_RENAME | NOTE_REVOKE, 0,
                   NULL);
            kevent(kq, &changes, 1, NULL, 0, NULL);
          }
          struct kevent event;
          int n = kevent(kq, NULL, 0, &event, 1, NULL);
          if (n > 0) {
            if (event.fflags &
                (NOTE_WRITE | NOTE_DELETE | NOTE_RENAME | NOTE_REVOKE)) {
              if (fd != -1)
                close(fd);
              fd = -1;
              dispatch_async(dispatch_get_main_queue(), ^{
                [self loadConfig];
              });
            }
          }
        }
      });
}
@end

int main(__unused int argc, __unused char *argv[]) {
  @autoreleasepool {
    [[ASConfigHelper shared] loadConfig];
    [[ASConfigHelper shared] startWatching];
    [[NSRunLoop currentRunLoop] run];
  }
  return 0;
}
