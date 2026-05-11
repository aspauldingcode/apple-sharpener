#import <Foundation/Foundation.h>
#import <notify.h>

// Embed version at compile time; defaults to "dev" when not provided
#ifndef APPLE_SHARPENER_VERSION
#define APPLE_SHARPENER_VERSION "dev"
#endif

void printUsage() {
    puts("Usage: sharpener [on|off|toggle] [options]\n"
         "\nCommands:"
         "\n  on, off, toggle        Control sharpening"
         "\n\nOptions:"
         "\n  -r, --radius <value>   Set sharpening radius"
         "\n  -d, --dock-radius <value>  Set dock radius"
         "\n  --shadows [on|off]     Toggle window shadows (default: on)"
         "\n  -s, --status           Show current radius and status"
         "\n  -v, --version          Show version"
         "\n  -h, --help             Show this help message\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            printUsage();
            return 1;
        }
        
        NSString *firstArg = [NSString stringWithUTF8String:argv[1]];
        
        if ([firstArg isEqualToString:@"--help"] || [firstArg isEqualToString:@"-h"]) {
            printUsage();
            return 0;
        }
        if ([firstArg isEqualToString:@"--version"] || [firstArg isEqualToString:@"-v"]) {
            printf("Apple Sharpener version: %s\n", APPLE_SHARPENER_VERSION);
            return 0;
        }
        
        if ([firstArg isEqualToString:@"on"]) {
            // Backward-compatible event
            notify_post("com.aspauldingcode.apple_sharpener.enable");
            // Persistent enabled state
            int tokenEnabled = 0;
            if (notify_register_check("com.aspauldingcode.apple_sharpener.enabled", &tokenEnabled) == NOTIFY_STATUS_OK) {
                notify_set_state(tokenEnabled, 1);
                notify_post("com.aspauldingcode.apple_sharpener.enabled");
            }
            NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
            [defaults setBool:YES forKey:@"enabled"];
            [defaults synchronize];
            printf("Sharpener enabled\n");
        } else if ([firstArg isEqualToString:@"off"]) {
            // Backward-compatible event
            notify_post("com.aspauldingcode.apple_sharpener.disable");
            // Persistent enabled state
            int tokenEnabled = 0;
            if (notify_register_check("com.aspauldingcode.apple_sharpener.enabled", &tokenEnabled) == NOTIFY_STATUS_OK) {
                notify_set_state(tokenEnabled, 0);
                notify_post("com.aspauldingcode.apple_sharpener.enabled");
            }
            NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
            [defaults setBool:NO forKey:@"enabled"];
            [defaults synchronize];
            printf("Sharpener disabled\n");
        } else if ([firstArg isEqualToString:@"toggle"]) {
            // Backward-compatible event
            notify_post("com.aspauldingcode.apple_sharpener.toggle");
            // Persistent enabled state toggle
            int tokenEnabled = 0;
            if (notify_register_check("com.aspauldingcode.apple_sharpener.enabled", &tokenEnabled) == NOTIFY_STATUS_OK) {
                uint64_t state = 0;
                notify_get_state(tokenEnabled, &state);
                uint64_t newState = (state == 0) ? 1 : 0;
                notify_set_state(tokenEnabled, newState);
                notify_post("com.aspauldingcode.apple_sharpener.enabled");
            }
            NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
            BOOL currentEnabled = [defaults boolForKey:@"enabled"];
            [defaults setBool:!currentEnabled forKey:@"enabled"];
            [defaults synchronize];
            printf("Sharpener toggled\n");
        } else if ([firstArg hasPrefix:@"--radius="] || ([firstArg isEqualToString:@"-r"] && argc > 2)) {
            uint64_t radius = 0;
            if ([firstArg hasPrefix:@"--radius="]) {
                radius = strtoull([[firstArg substringFromIndex:9] UTF8String], NULL, 10);
            } else {
                radius = strtoull(argv[2], NULL, 10);
            }
            // Register for the set_radius notification to obtain a token.
            int tokenSetRadius = 0;
            if (notify_register_check("com.aspauldingcode.apple_sharpener.set_radius", &tokenSetRadius) == NOTIFY_STATUS_OK) {
                // Set the state with the token and post the notification.
                notify_set_state(tokenSetRadius, radius);
                notify_post("com.aspauldingcode.apple_sharpener.set_radius");
                NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
                [defaults setInteger:radius forKey:@"radius"];
                [defaults synchronize];
                printf("Sharpener radius set to %llu\n", radius);
            } else {
                printf("Failed to register set_radius notification\n");
                return 1;
            }
        } else if ([firstArg hasPrefix:@"--dock-radius="] || [firstArg hasPrefix:@"-d="] || ([firstArg isEqualToString:@"--dock-radius"] && argc > 2) || ([firstArg isEqualToString:@"-d"] && argc > 2)) {
            uint64_t radius = 0;
            if ([firstArg hasPrefix:@"--dock-radius="]) {
                radius = strtoull([[firstArg substringFromIndex:14] UTF8String], NULL, 10);
            } else if ([firstArg hasPrefix:@"-d="]) {
                radius = strtoull([[firstArg substringFromIndex:3] UTF8String], NULL, 10);
            } else {
                radius = strtoull(argv[2], NULL, 10);
            }
            int tokenSetRadius = 0;
            if (notify_register_check("com.aspauldingcode.apple_sharpener.dock.set_radius", &tokenSetRadius) == NOTIFY_STATUS_OK) {
                notify_set_state(tokenSetRadius, radius);
                notify_post("com.aspauldingcode.apple_sharpener.dock.set_radius");
                NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
                [defaults setInteger:radius forKey:@"dock_radius"];
                [defaults synchronize];
                printf("Dock radius set to %llu\n", radius);
            } else {
                printf("Failed to register dock set_radius notification\n");
                return 1;
            }
        } else if ([firstArg isEqualToString:@"--shadows"] && argc > 2) {
            NSString *shadowArg = [NSString stringWithUTF8String:argv[2]];
            BOOL remove = NO;
            if ([shadowArg isEqualToString:@"off"]) {
                remove = YES;
            } else if ([shadowArg isEqualToString:@"on"]) {
                remove = NO;
            } else {
                printf("Invalid shadow state: %s. Use 'on' or 'off'.\n", [shadowArg UTF8String]);
                return 1;
            }
            
            int tokenShadows = 0;
            if (notify_register_check("com.aspauldingcode.apple_sharpener.remove_shadows", &tokenShadows) == NOTIFY_STATUS_OK) {
                notify_set_state(tokenShadows, remove);
                notify_post("com.aspauldingcode.apple_sharpener.remove_shadows");
                NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
                [defaults setBool:remove forKey:@"remove_shadows"];
                [defaults synchronize];
                printf("Window shadows %s\n", remove ? "disabled" : "enabled");
            } else {
                printf("Failed to register shadows notification\n");
                return 1;
            }
        } else if ([firstArg isEqualToString:@"--status"] || [firstArg isEqualToString:@"-s"]) {
            // Read the current radius from the shared state on the set_radius channel
            int tokenShowRadius = 0;
            uint64_t currentRadius = 0;
            if (notify_register_check("com.aspauldingcode.apple_sharpener.set_radius", &tokenShowRadius) == NOTIFY_STATUS_OK) {
                if (notify_get_state(tokenShowRadius, &currentRadius) != NOTIFY_STATUS_OK) {
                    printf("Failed to read current radius\n");
                    return 1;
                }
            } else {
                printf("Failed to register set_radius notification for reading\n");
                return 1;
            }

            // Read dock radius from the shared state
            int tokenDockRadius = 0;
            uint64_t currentDockRadius = 0;
            if (notify_register_check("com.aspauldingcode.apple_sharpener.dock.set_radius", &tokenDockRadius) == NOTIFY_STATUS_OK) {
                if (notify_get_state(tokenDockRadius, &currentDockRadius) != NOTIFY_STATUS_OK) {
                    printf("Failed to read current dock radius\n");
                    return 1;
                }
            } else {
                printf("Failed to register dock set_radius notification for reading\n");
                return 1;
            }

            // Read enabled status from persistent state
            int tokenEnabled = 0;
            uint64_t enabledState = 0;
            if (notify_register_check("com.aspauldingcode.apple_sharpener.enabled", &tokenEnabled) == NOTIFY_STATUS_OK) {
                if (notify_get_state(tokenEnabled, &enabledState) != NOTIFY_STATUS_OK) {
                    printf("Failed to read current status\n");
                    return 1;
                }
            } else {
                printf("Failed to register enabled notification for reading\n");
                return 1;
            }
            NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
            BOOL persistedEnabled = [defaults boolForKey:@"enabled"];
            BOOL removeShadows = [defaults boolForKey:@"remove_shadows"];
            enabledState = persistedEnabled ? 1 : 0;  // Use persisted value if needed
            printf("Current radius: %llu\n", currentRadius);
            printf("Current dock radius: %llu\n", currentDockRadius);
            printf("Window shadows: %s\n", removeShadows ? "off" : "on");
            printf("Status: %s\n", enabledState ? "on" : "off");
        } else {
            printf("Unknown command: %s\n", [firstArg UTF8String]);
            printUsage();
            return 1;
        }
    }
    return 0;
}
