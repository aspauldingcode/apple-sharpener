/**
 * Apple Sharpener: Command Line Interface
 *
 * Provides a terminal-based interface for controlling sharpening settings,
 * broadcasting notifications, and viewing current status.
 */

#import <Foundation/Foundation.h>
#import <notify.h>
#import "sharpener_cf_prefs.h"
#import "kdl_patch.h"

// Embed version at compile time; defaults to "dev" when not provided
#ifndef APPLE_SHARPENER_VERSION
#define APPLE_SHARPENER_VERSION "dev"
#endif

static void sharpener_cli_commit(void) {
  // Authoritative settings reside in the shared suite
  NSUserDefaults *suite =
      [[NSUserDefaults alloc] initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
  // Mirror to CF domain so all processes can see the change immediately
  SharpenerMirrorSuiteDefaultsToCF(suite);
  // Broadcast update notification to all listeners (Dock, Apps)
  SharpenerPostModulesUpdateNotification();
}

void printUsage() {
  puts("Usage: sharpener [command] [options]\n"
       "\nGlobal Commands:"
       "\n  on, off, toggle              Control sharpening (windows and dock; "
       "`off` / disable toggle also turns squircle off)"
       "\n  -r, --radius <value>         Set global radius (affects windows "
       "and dock)"
       "\n\nWindows Commands:"
       "\n  -w, --windows on|off|toggle  Control windows only"
       "\n  -w, --windows <value>        Set windows-specific radius"
       "\n\nDock Commands:"
       "\n  -d, --dock on|off|toggle     Control dock only"
       "\n  -d, --dock <value>           Set dock-specific radius (alias for "
       "--dock-radius)"
       "\n\nSquircle Commands:"
       "\n  -q, --squircle on|off|toggle Control continuous corners (squircles)"
       "\n  -e, --exponent <value>       Set squircle exponent (0-6, default: "
       "4.0)"
       "\n\nOther Options:"
       "\n  -s, --status                 Show current radius and status"
       "\n  --json                       Show status as JSON"
       "\n  -v, --version                Show version"
       "\n  -h, --help                   Show this help message\n");
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc < 2) {
      printUsage();
      return 1;
    }

    NSString *firstArg = [NSString stringWithUTF8String:argv[1]];

    if ([firstArg isEqualToString:@"--help"] ||
        [firstArg isEqualToString:@"-h"]) {
      printUsage();
      return 0;
    }
    if ([firstArg isEqualToString:@"--version"] ||
        [firstArg isEqualToString:@"-v"]) {
      printf("Apple Sharpener version: %s\n", APPLE_SHARPENER_VERSION);
      return 0;
    }

    // Check for -w/--windows or -d/--dock or -q/--squircle or -e/--exponent
    // flags
    BOOL isWindowsOnly = NO;
    BOOL isDockOnly = NO;
    BOOL isSquircleOnly = NO;
    BOOL isExponentOnly = NO;
    NSString *command = firstArg;
    BOOL isRadiusCommand = NO;

    if ([firstArg isEqualToString:@"-w"] ||
        [firstArg isEqualToString:@"--windows"]) {
      isWindowsOnly = YES;
      if (argc < 3) {
        printf(
            "Error: -w/--windows requires a value (on/off/toggle or radius)\n");
        printUsage();
        return 1;
      }
      NSString *secondArg = [NSString stringWithUTF8String:argv[2]];
      // Check if it's a number (radius) or a command (on/off/toggle)
      char *endptr;
      strtoull([secondArg UTF8String], &endptr, 10);
      if (*endptr == '\0' && secondArg.length > 0) {
        // It's a number - treat as radius
        isRadiusCommand = YES;
        command = secondArg;
      } else {
        // It's a command - treat as toggle
        command = secondArg;
      }
    } else if ([firstArg isEqualToString:@"-d"] ||
               [firstArg isEqualToString:@"--dock"]) {
      isDockOnly = YES;
      if (argc < 3) {
        printf("Error: -d/--dock requires a value (on/off/toggle or radius)\n");
        printUsage();
        return 1;
      }
      NSString *secondArg = [NSString stringWithUTF8String:argv[2]];
      // Check if it's a number (radius) or a command (on/off/toggle)
      char *endptr;
      strtoull([secondArg UTF8String], &endptr, 10);
      if (*endptr == '\0' && secondArg.length > 0) {
        // It's a number - treat as radius
        isRadiusCommand = YES;
        command = secondArg;
      } else {
        // It's a command - treat as toggle
        command = secondArg;
      }
    } else if ([firstArg isEqualToString:@"-q"] ||
               [firstArg isEqualToString:@"--squircle"]) {
      isSquircleOnly = YES;
      if (argc < 3) {
        printf("Error: -q/--squircle requires a value (on/off/toggle)\n");
        printUsage();
        return 1;
      }
      NSString *secondArg = [NSString stringWithUTF8String:argv[2]];
      command = secondArg;
    } else if ([firstArg isEqualToString:@"-e"] ||
               [firstArg isEqualToString:@"--exponent"]) {
      isExponentOnly = YES;
      if (argc < 3) {
        printf("Error: -e/--exponent requires a floating-point value (e.g. "
               "4.0)\n");
        printUsage();
        return 1;
      }
      NSString *secondArg = [NSString stringWithUTF8String:argv[2]];
      command = secondArg;
    }

    // Handle radius commands first (before toggle commands)
    if (isRadiusCommand) {
      NSUserDefaults *defaults = [[NSUserDefaults alloc]
          initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
      uint64_t radius = strtoull([command UTF8String], NULL, 10);

      // Validate radius limits
      uint64_t minRadius = 0;
      uint64_t maxRadius;
      const char *componentName;

      if (isWindowsOnly) {
        maxRadius = 100;
        componentName = "Windows";
      } else if (isDockOnly) {
        maxRadius = 46;
        componentName = "Dock";
      } else {
        // This shouldn't happen for global radius in this code path
        // Global radius is handled separately below
        maxRadius = 100;
        componentName = "Global";
      }

      if (radius < minRadius || radius > maxRadius) {
        printf("Error: %s radius must be between %llu and %llu (got %llu)\n",
               componentName, minRadius, maxRadius, radius);
        return 1;
      }

      if (isWindowsOnly) {
        // Windows-specific radius
        int tokenSetRadius = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.windows.set_radius",
                &tokenSetRadius) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenSetRadius, radius);
          notify_post("com.aspauldingcode.apple_sharpener.windows.set_radius");
        }
        [defaults setInteger:radius forKey:@"windows_radius"];
        [defaults synchronize];
        kdl_set_int(@"windows", @"radius", (NSInteger)radius);
        printf("Windows radius set to %llu\n", radius);
        sharpener_cli_commit();
        return 0;
      } else if (isDockOnly) {
        // Dock-specific radius
        int tokenSetRadius = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.dock.set_radius",
                &tokenSetRadius) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenSetRadius, radius);
          notify_post("com.aspauldingcode.apple_sharpener.dock.set_radius");
        }
        [defaults setInteger:radius forKey:@"dock_radius"];
        [defaults synchronize];
        kdl_set_int(@"dock", @"radius", (NSInteger)radius);
        printf("Dock radius set to %llu\n", radius);
        sharpener_cli_commit();
        return 0;
      }
    }

    if (isExponentOnly) {
      NSUserDefaults *defaults = [[NSUserDefaults alloc]
          initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
      double requestedExponent = [command doubleValue];
      double exponent = requestedExponent;
      if (exponent <= 0)
        exponent = 1e-7; // Epsilon trick, same as radius=0
      if (exponent > 6.0)
        exponent = 6.0; // Cap at maximum
      [defaults setDouble:exponent forKey:@"squircle_exponent"];
      [defaults synchronize];
      kdl_set_double(@"global", @"squircle_exponent", exponent);

      int tokenEnabled = 0;
      if (notify_register_check(
              "com.aspauldingcode.apple_sharpener.squircle.exponent",
              &tokenEnabled) == NOTIFY_STATUS_OK) {
        notify_set_state(tokenEnabled, 1);
        notify_post("com.aspauldingcode.apple_sharpener.squircle.exponent");
      }

      // Ping the windows radius update to force a visual redraw immediately
      int tokenWindowsRadius = 0;
      if (notify_register_check(
              "com.aspauldingcode.apple_sharpener.windows.set_radius",
              &tokenWindowsRadius) == NOTIFY_STATUS_OK) {
        notify_set_state(tokenWindowsRadius,
                         [defaults integerForKey:@"windows_radius"]);
        notify_post("com.aspauldingcode.apple_sharpener.windows.set_radius");
      }

      if (requestedExponent > 6.0) {
        printf("Squircle exponent set to %.2f (capped at maximum of 6.0, "
               "requested: %.2f)\n",
               exponent, requestedExponent);
      } else {
        printf("Squircle exponent set to %.2f\n", exponent);
      }
      sharpener_cli_commit();
      return 0;
    }

    // Handle toggle commands
    if ([command isEqualToString:@"on"]) {
      NSUserDefaults *defaults = [[NSUserDefaults alloc]
          initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];

      if (isWindowsOnly) {
        // Windows only
        int tokenEnabled = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.windows.enabled",
                &tokenEnabled) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenEnabled, 1);
          notify_post("com.aspauldingcode.apple_sharpener.windows.enabled");
        }
        [defaults setBool:YES forKey:@"windows_enabled"];
        [defaults synchronize];
        kdl_set_bool(@"windows", @"enabled", YES);
        printf("Windows sharpener enabled\n");
      } else if (isDockOnly) {
        // Dock only
        int tokenEnabled = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.dock.enabled",
                &tokenEnabled) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenEnabled, 1);
          notify_post("com.aspauldingcode.apple_sharpener.dock.enabled");
        }
        [defaults setBool:YES forKey:@"dock_enabled"];
        [defaults synchronize];
        kdl_set_bool(@"dock", @"enabled", YES);
        printf("Dock sharpener enabled\n");
      } else if (isSquircleOnly) {
        // Squircle only
        int tokenEnabled = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.squircle.enabled",
                &tokenEnabled) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenEnabled, 1);
          notify_post("com.aspauldingcode.apple_sharpener.squircle.enabled");
        }

        // Ping the windows radius update to force a visual redraw immediately
        int tokenWindowsRadius = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.windows.set_radius",
                &tokenWindowsRadius) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenWindowsRadius,
                           [defaults integerForKey:@"windows_radius"]);
          notify_post("com.aspauldingcode.apple_sharpener.windows.set_radius");
        }

        [defaults setBool:YES forKey:@"squircle_enabled"];
        [defaults synchronize];
        kdl_set_bool(@"global", @"squircle", YES);
        printf("Squircle continuous corners enabled\n");
      } else {
        // Both (global)
        notify_post("com.aspauldingcode.apple_sharpener.enable");
        int tokenEnabled = 0;
        if (notify_register_check("com.aspauldingcode.apple_sharpener.enabled",
                                  &tokenEnabled) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenEnabled, 1);
          notify_post("com.aspauldingcode.apple_sharpener.enabled");
        }
        // Also set windows and dock separately
        int tokenWindows = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.windows.enabled",
                &tokenWindows) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenWindows, 1);
          notify_post("com.aspauldingcode.apple_sharpener.windows.enabled");
        }
        int tokenDock = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.dock.enabled",
                &tokenDock) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenDock, 1);
          notify_post("com.aspauldingcode.apple_sharpener.dock.enabled");
        }
        [defaults setBool:YES forKey:@"enabled"];
        [defaults synchronize];
        kdl_set_bool(@"sharpener", @"enabled", YES);
        printf("Sharpener enabled (windows and dock)\n");
      }
      sharpener_cli_commit();
    } else if ([command isEqualToString:@"off"]) {
      NSUserDefaults *defaults = [[NSUserDefaults alloc]
          initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];

      if (isWindowsOnly) {
        // Windows only
        int tokenEnabled = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.windows.enabled",
                &tokenEnabled) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenEnabled, 0);
          notify_post("com.aspauldingcode.apple_sharpener.windows.enabled");
        }
        [defaults setBool:NO forKey:@"windows_enabled"];
        [defaults synchronize];
        kdl_set_bool(@"windows", @"enabled", NO);
        printf("Windows sharpener disabled\n");
      } else if (isDockOnly) {
        // Dock only
        int tokenEnabled = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.dock.enabled",
                &tokenEnabled) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenEnabled, 0);
          notify_post("com.aspauldingcode.apple_sharpener.dock.enabled");
        }
        [defaults setBool:NO forKey:@"dock_enabled"];
        [defaults synchronize];
        kdl_set_bool(@"dock", @"enabled", NO);
        printf("Dock sharpener disabled\n");
      } else if (isSquircleOnly) {
        // Squircle only
        int tokenEnabled = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.squircle.enabled",
                &tokenEnabled) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenEnabled, 0);
          notify_post("com.aspauldingcode.apple_sharpener.squircle.enabled");
        }

        // Ping the windows radius update to force a visual redraw immediately
        int tokenWindowsRadius = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.windows.set_radius",
                &tokenWindowsRadius) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenWindowsRadius,
                           [defaults integerForKey:@"windows_radius"]);
          notify_post("com.aspauldingcode.apple_sharpener.windows.set_radius");
        }

        [defaults setBool:NO forKey:@"squircle_enabled"];
        [defaults synchronize];
        kdl_set_bool(@"global", @"squircle", NO);
        printf("Squircle continuous corners disabled\n");
      } else {
        // Both (global)
        notify_post("com.aspauldingcode.apple_sharpener.disable");
        int tokenEnabled = 0;
        if (notify_register_check("com.aspauldingcode.apple_sharpener.enabled",
                                  &tokenEnabled) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenEnabled, 0);
          notify_post("com.aspauldingcode.apple_sharpener.enabled");
        }
        // Also set windows and dock separately
        int tokenWindows = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.windows.enabled",
                &tokenWindows) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenWindows, 0);
          notify_post("com.aspauldingcode.apple_sharpener.windows.enabled");
        }
        int tokenDock = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.dock.enabled",
                &tokenDock) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenDock, 0);
          notify_post("com.aspauldingcode.apple_sharpener.dock.enabled");
        }
        [defaults setBool:NO forKey:@"enabled"];
        [defaults synchronize];
        kdl_set_bool(@"sharpener", @"enabled", NO);
        printf("Sharpener disabled (windows, dock, and squircle)\n");
      }
      sharpener_cli_commit();
    } else if ([command isEqualToString:@"toggle"]) {
      NSUserDefaults *defaults = [[NSUserDefaults alloc]
          initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];

      if (isWindowsOnly) {
        // Windows only
        BOOL currentEnabled = [defaults boolForKey:@"windows_enabled"];
        BOOL newEnabled = !currentEnabled;

        int tokenEnabled = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.windows.enabled",
                &tokenEnabled) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenEnabled, newEnabled ? 1 : 0);
          notify_post("com.aspauldingcode.apple_sharpener.windows.enabled");
        }
        [defaults setBool:newEnabled forKey:@"windows_enabled"];
        [defaults synchronize];
        printf("Windows sharpener %s\n", newEnabled ? "enabled" : "disabled");
      } else if (isDockOnly) {
        // Dock only
        BOOL currentEnabled = [defaults boolForKey:@"dock_enabled"];
        BOOL newEnabled = !currentEnabled;

        int tokenEnabled = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.dock.enabled",
                &tokenEnabled) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenEnabled, newEnabled ? 1 : 0);
          notify_post("com.aspauldingcode.apple_sharpener.dock.enabled");
        }
        [defaults setBool:newEnabled forKey:@"dock_enabled"];
        [defaults synchronize];
        printf("Dock sharpener %s\n", newEnabled ? "enabled" : "disabled");
      } else if (isSquircleOnly) {
        // Squircle only
        BOOL currentEnabled = YES;
        if ([defaults objectForKey:@"squircle_enabled"] != nil) {
          currentEnabled = [defaults boolForKey:@"squircle_enabled"];
        }
        BOOL newEnabled = !currentEnabled;

        int tokenEnabled = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.squircle.enabled",
                &tokenEnabled) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenEnabled, newEnabled ? 1 : 0);
          notify_post("com.aspauldingcode.apple_sharpener.squircle.enabled");
        }

        // Ping the windows radius update to force a visual redraw immediately
        int tokenWindowsRadius = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.windows.set_radius",
                &tokenWindowsRadius) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenWindowsRadius,
                           [defaults integerForKey:@"windows_radius"]);
          notify_post("com.aspauldingcode.apple_sharpener.windows.set_radius");
        }

        [defaults setBool:newEnabled forKey:@"squircle_enabled"];
        [defaults synchronize];
        printf("Squircle continuous corners %s\n",
               newEnabled ? "enabled" : "disabled");
      } else {
        // Both (global)
        BOOL currentEnabled = YES;
        if ([defaults objectForKey:@"enabled"] != nil) {
          currentEnabled = [defaults boolForKey:@"enabled"];
        }
        BOOL newEnabled = !currentEnabled;

        notify_post("com.aspauldingcode.apple_sharpener.toggle");
        int tokenEnabled = 0;
        if (notify_register_check("com.aspauldingcode.apple_sharpener.enabled",
                                  &tokenEnabled) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenEnabled, newEnabled ? 1 : 0);
          notify_post("com.aspauldingcode.apple_sharpener.enabled");
        }
        // Also toggle windows and dock separately
        int tokenWindows = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.windows.enabled",
                &tokenWindows) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenWindows, newEnabled ? 1 : 0);
          notify_post("com.aspauldingcode.apple_sharpener.windows.enabled");
        }
        int tokenDock = 0;
        if (notify_register_check(
                "com.aspauldingcode.apple_sharpener.dock.enabled",
                &tokenDock) == NOTIFY_STATUS_OK) {
          notify_set_state(tokenDock, newEnabled ? 1 : 0);
          notify_post("com.aspauldingcode.apple_sharpener.dock.enabled");
        }
        [defaults setBool:newEnabled forKey:@"enabled"];
        [defaults synchronize];
        if (newEnabled) {
          printf("Sharpener enabled (windows and dock)\n");
        } else {
          printf("Sharpener disabled (windows, dock, and squircle)\n");
        }
      }
      sharpener_cli_commit();
      return 0;
    } else if ([firstArg hasPrefix:@"--radius="] ||
               ([firstArg isEqualToString:@"-r"] && argc > 2) ||
               [firstArg isEqualToString:@"--radius"]) {
      uint64_t radius = 0;
      if ([firstArg hasPrefix:@"--radius="]) {
        radius =
            strtoull([[firstArg substringFromIndex:9] UTF8String], NULL, 10);
      } else {
        radius = strtoull(argv[2], NULL, 10);
      }

      // Validate global radius (0-100, dock will be capped at 46)
      if (radius < 0 || radius > 100) {
        printf("Error: Global radius must be between 0 and 100 (got %llu)\n",
               radius);
        return 1;
      }

      NSUserDefaults *defaults = [[NSUserDefaults alloc]
          initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];

      // Set global radius (affects both windows and dock)
      int tokenSetRadius = 0;
      if (notify_register_check("com.aspauldingcode.apple_sharpener.set_radius",
                                &tokenSetRadius) == NOTIFY_STATUS_OK) {
        notify_set_state(tokenSetRadius, radius);
        notify_post("com.aspauldingcode.apple_sharpener.set_radius");
      }
      // Set windows to the full radius value
      int tokenWindowsRadius = 0;
      if (notify_register_check(
              "com.aspauldingcode.apple_sharpener.windows.set_radius",
              &tokenWindowsRadius) == NOTIFY_STATUS_OK) {
        notify_set_state(tokenWindowsRadius, radius);
        notify_post("com.aspauldingcode.apple_sharpener.windows.set_radius");
      }
      // Cap dock at 46 if global radius exceeds dock's maximum
      uint64_t dockRadius = (radius > 46) ? 46 : radius;
      int tokenDockRadius = 0;
      if (notify_register_check(
              "com.aspauldingcode.apple_sharpener.dock.set_radius",
              &tokenDockRadius) == NOTIFY_STATUS_OK) {
        notify_set_state(tokenDockRadius, dockRadius);
        notify_post("com.aspauldingcode.apple_sharpener.dock.set_radius");
      }
      [defaults setInteger:radius forKey:@"radius"];
      [defaults setInteger:radius forKey:@"windows_radius"];
      [defaults setInteger:dockRadius forKey:@"dock_radius"];
      [defaults synchronize];
      kdl_set_int(@"global", @"radius", (NSInteger)radius);
      kdl_set_int(@"windows", @"radius", (NSInteger)radius);
      kdl_set_int(@"dock", @"radius", (NSInteger)dockRadius);
      if (radius > 46) {
        printf("Global radius set to %llu (windows: %llu, dock: %llu - capped "
               "at maximum)\n",
               radius, radius, dockRadius);
      } else {
        printf("Global radius set to %llu (windows and dock)\n", radius);
      }
      sharpener_cli_commit();
      return 0;
    } else if ([firstArg hasPrefix:@"--dock-radius="] ||
               ([firstArg isEqualToString:@"--dock-radius"] && argc > 2)) {
      // Support --dock-radius for backward compatibility, but -d is preferred
      uint64_t radius = 0;
      if ([firstArg hasPrefix:@"--dock-radius="]) {
        radius =
            strtoull([[firstArg substringFromIndex:14] UTF8String], NULL, 10);
      } else {
        radius = strtoull(argv[2], NULL, 10);
      }

      // Validate dock radius (0-46)
      if (radius < 0 || radius > 46) {
        printf("Error: Dock radius must be between 0 and 46 (got %llu)\n",
               radius);
        return 1;
      }

      int tokenSetRadius = 0;
      if (notify_register_check(
              "com.aspauldingcode.apple_sharpener.dock.set_radius",
              &tokenSetRadius) == NOTIFY_STATUS_OK) {
        notify_set_state(tokenSetRadius, radius);
        notify_post("com.aspauldingcode.apple_sharpener.dock.set_radius");
        NSUserDefaults *defaults = [[NSUserDefaults alloc]
            initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
        [defaults setInteger:radius forKey:@"dock_radius"];
        [defaults synchronize];
        kdl_set_int(@"dock", @"radius", (NSInteger)radius);
        printf("Dock radius set to %llu\n", radius);
        sharpener_cli_commit();
      } else {
        printf("Failed to register dock set_radius notification\n");
        return 1;
      }
      return 0;
    } else if ([firstArg isEqualToString:@"--status"] ||
               [firstArg isEqualToString:@"-s"] ||
               [firstArg isEqualToString:@"--json"]) {
      BOOL jsonOutput = [firstArg isEqualToString:@"--json"];

      NSUserDefaults *defaults = [[NSUserDefaults alloc]
          initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];

      // Read global radius - first check notify state, fall back to defaults
      int tokenShowRadius = 0;
      uint64_t currentRadius = 0;
      if (notify_register_check("com.aspauldingcode.apple_sharpener.set_radius",
                                &tokenShowRadius) == NOTIFY_STATUS_OK) {
        notify_get_state(tokenShowRadius, &currentRadius);
      }
      // Authoritative: always prefer NSUserDefaults value if set
      if ([defaults objectForKey:@"radius"] != nil) {
        currentRadius = [defaults integerForKey:@"radius"];
      }

      uint64_t currentWindowsRadius =
          [defaults integerForKey:@"windows_radius"];
      if (currentWindowsRadius == 0)
        currentWindowsRadius = currentRadius;

      // Dock radius: try notify state, fall back to defaults
      int tokenDockRadius = 0;
      uint64_t currentDockRadius = 0;
      if (notify_register_check(
              "com.aspauldingcode.apple_sharpener.dock.set_radius",
              &tokenDockRadius) == NOTIFY_STATUS_OK) {
        notify_get_state(tokenDockRadius, &currentDockRadius);
      }
      if ([defaults objectForKey:@"dock_radius"] != nil) {
        currentDockRadius = [defaults integerForKey:@"dock_radius"];
      }
      if (currentDockRadius == 0)
        currentDockRadius = currentRadius;

      // Boolean states — read from NSUserDefaults (authoritative source)
      BOOL windowsEnabled = [defaults objectForKey:@"windows_enabled"] != nil
                                ? [defaults boolForKey:@"windows_enabled"]
                                : YES;
      BOOL dockEnabled = [defaults objectForKey:@"dock_enabled"] != nil
                             ? [defaults boolForKey:@"dock_enabled"]
                             : YES;
      BOOL globalEnabled = [defaults objectForKey:@"enabled"] != nil
                               ? [defaults boolForKey:@"enabled"]
                               : YES;
      BOOL squircleEnabled = [defaults objectForKey:@"squircle_enabled"] != nil
                                 ? [defaults boolForKey:@"squircle_enabled"]
                                 : YES;
      double squircleExponent =
          [defaults objectForKey:@"squircle_exponent"] != nil
              ? [defaults doubleForKey:@"squircle_exponent"]
              : 4.0;

      if (jsonOutput) {
        printf("{\n"
               "  \"global\": {\n"
               "    \"enabled\": %s,\n"
               "    \"radius\": %llu\n"
               "  },\n"
               "  \"windows\": {\n"
               "    \"enabled\": %s,\n"
               "    \"radius\": %llu\n"
               "  },\n"
               "  \"dock\": {\n"
               "    \"enabled\": %s,\n"
               "    \"radius\": %llu\n"
               "  },\n"
               "  \"squircle\": {\n"
               "    \"enabled\": %s,\n"
               "    \"exponent\": %.2f\n"
               "  }\n"
               "}\n",
               globalEnabled ? "true" : "false", currentRadius,
               windowsEnabled ? "true" : "false", currentWindowsRadius,
               dockEnabled ? "true" : "false", currentDockRadius,
               squircleEnabled ? "true" : "false", squircleExponent);
      } else {
        printf("\n"
               "  Apple Sharpener  %s\n"
               "  ─────────────────────────\n"
               "  Global     %-3s   radius: %llu\n"
               "  Windows    %-3s   radius: %llu\n"
               "  Dock       %-3s   radius: %llu\n"
               "  Squircle   %-3s   exponent: %.2f\n"
               "\n",
               globalEnabled ? "●" : "○", globalEnabled ? "on" : "off",
               currentRadius, windowsEnabled ? "on" : "off",
               currentWindowsRadius, dockEnabled ? "on" : "off",
               currentDockRadius, squircleEnabled ? "on" : "off",
               squircleExponent);
      }
      return 0;
    } else {
      printf("Unknown command: %s\n", [firstArg UTF8String]);
      printUsage();
      return 1;
    }
  }
  return 0;
}
