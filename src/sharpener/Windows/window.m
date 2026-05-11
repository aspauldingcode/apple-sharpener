#import <AppKit/AppKit.h>
#import "ZKSwizzle.h"
#import <notify.h>

/**
 * Window sharpening implementation for apple-sharpener
 * Contains swizzled implementations to enforce custom window corner radius on macOS application windows.
 * When enabled, the tweak overrides the default corner radius by setting the window's cornerRadius property.
 */

#pragma mark - Global State

static BOOL enableSharpener = YES;
static BOOL enableCustomRadius = YES;
static NSInteger customRadius = 0;
static BOOL removeShadows = NO;

#pragma mark - Forward Declarations

void toggleSquareCorners(BOOL enable, NSInteger radius);
void toggleWindowShadows(BOOL remove);
static void setupWindowNotifications(void) __attribute__((constructor));

#pragma mark - Helper Functions

// Check if a window is a standard application window.
// Inlined for performance since it's called frequently
static inline BOOL isStandardAppWindow(NSWindow *window) {
    if (!window) return NO;
    NSWindowStyleMask mask = window.styleMask;
    
    // Only apply to standard titled windows
    if (!(mask & NSWindowStyleMaskTitled)) return NO;
    
    // Exclude HUD, utility, and other system windows
    if (mask & (NSWindowStyleMaskHUDWindow | NSWindowStyleMaskUtilityWindow)) return NO;
    
    // Exclude very small windows (likely UI elements)
    NSRect frame = window.frame;
    if (frame.size.width < 100 || frame.size.height < 50) return NO;
    
    return YES;
}

static void applyCornerRadiusToWindow(NSWindow *window) {
    if (!window || !enableSharpener) return;
    if (!isStandardAppWindow(window)) return;
    
    if (enableSharpener && enableCustomRadius) {
        [(id)window setValue:@(customRadius) forKey:@"cornerRadius"];
    }
    
    if (removeShadows) {
        [window setHasShadow:NO];
    } else {
        [window setHasShadow:YES];
    }
    
    [window invalidateShadow];
}

#pragma mark - Public API

void toggleSquareCorners(BOOL enable, NSInteger radius) {
    BOOL stateChanged = (enableSharpener != enable || customRadius != MAX(0, radius));
    
    enableSharpener = enable;
    customRadius = MAX(0, radius);
    
    if (stateChanged) {
        for (NSWindow *window in [NSApplication sharedApplication].windows) {
            if (enableSharpener) {
                applyCornerRadiusToWindow(window);
            } else if (isStandardAppWindow(window)) {
                [(id)window setValue:@0 forKey:@"cornerRadius"];
                [window setHasShadow:YES];
                [window invalidateShadow];
            }
        }
    }
}

void toggleWindowShadows(BOOL remove) {
    BOOL stateChanged = (removeShadows != remove);
    removeShadows = remove;
    
    if (stateChanged) {
        for (NSWindow *window in [NSApplication sharedApplication].windows) {
            if (enableSharpener) {
                applyCornerRadiusToWindow(window);
            } else if (isStandardAppWindow(window)) {
                [window setHasShadow:!removeShadows];
                [window invalidateShadow];
            }
        }
    }
}

#pragma mark - Notification Setup

static void setupWindowNotifications(void) {
    // Perform grouped swizzling after +load has run to avoid class-method collisions
    ZKSwizzleGroup(APPLE_SHARPENER);

    dispatch_queue_t queue = dispatch_get_main_queue();

    static const char *kNotifyRadius  = "com.aspauldingcode.apple_sharpener.set_radius";
    static const char *kNotifyShadows = "com.aspauldingcode.apple_sharpener.remove_shadows";

    // Load persisted state from NSUserDefaults
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
    enableSharpener = [defaults boolForKey:@"enabled"];
    customRadius = [defaults integerForKey:@"radius"];
    removeShadows = [defaults boolForKey:@"remove_shadows"];

    // Add observers for multiple window events to catch all window creation scenarios
    // Add observers for window events to apply corner radius when windows become active
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeMainNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
        applyCornerRadiusToWindow(notification.object);
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
        applyCornerRadiusToWindow(notification.object);
    }];

    toggleSquareCorners(enableSharpener, customRadius);

    int tokenEnable = 0;
    notify_register_dispatch("com.aspauldingcode.apple_sharpener.enable", &tokenEnable, queue, ^(int __unused t){
        toggleSquareCorners(YES, customRadius);
        [defaults setBool:YES forKey:@"enabled"];
        [defaults setInteger:customRadius forKey:@"radius"];
        [defaults synchronize];
    });

    int tokenDisable = 0;
    notify_register_dispatch("com.aspauldingcode.apple_sharpener.disable", &tokenDisable, queue, ^(int __unused t){
        toggleSquareCorners(NO, customRadius);
        [defaults setBool:NO forKey:@"enabled"];
        [defaults setInteger:customRadius forKey:@"radius"];
        [defaults synchronize];
    });

    int tokenToggle = 0;
    notify_register_dispatch("com.aspauldingcode.apple_sharpener.toggle", &tokenToggle, queue, ^(int __unused t){
        toggleSquareCorners(!enableSharpener, customRadius);
        [defaults setBool:enableSharpener forKey:@"enabled"];
        [defaults setInteger:customRadius forKey:@"radius"];
        [defaults synchronize];
    });

    int tokenSetRadius = 0;
    notify_register_dispatch(kNotifyRadius, &tokenSetRadius, queue, ^(int t){
        uint64_t state = 0;
        if (notify_get_state(t, &state) == NOTIFY_STATUS_OK) {
            toggleSquareCorners(enableSharpener, (NSInteger)state);
        }
        [defaults setBool:enableSharpener forKey:@"enabled"];
        [defaults setInteger:customRadius forKey:@"radius"];
        [defaults synchronize];
    });

    int tokenShadows = 0;
    notify_register_dispatch(kNotifyShadows, &tokenShadows, queue, ^(int t){
        uint64_t state = 0;
        if (notify_get_state(t, &state) == NOTIFY_STATUS_OK) {
            toggleWindowShadows((BOOL)state);
        }
        [defaults setBool:removeShadows forKey:@"remove_shadows"];
        [defaults synchronize];
    });
}

#pragma mark - Swizzled NSWindow

 ZKSwizzleInterfaceGroup(AS_NSWindow_CornerRadius, NSWindow, NSWindow, APPLE_SHARPENER)
@implementation AS_NSWindow_CornerRadius

- (BOOL)hasShadow {
    if (removeShadows && isStandardAppWindow(self)) {
        return NO;
    }
    return ZKOrig(BOOL);
}

- (void)setHasShadow:(BOOL)hasShadow {
    if (removeShadows && isStandardAppWindow(self)) {
        ZKOrig(void, NO);
    } else {
        ZKOrig(void, hasShadow);
    }
}

- (void)setFrame:(NSRect)frameRect display:(BOOL)flag {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, frameRect, flag);
#pragma clang diagnostic pop
    if (enableSharpener && enableCustomRadius && isStandardAppWindow(self))
        applyCornerRadiusToWindow(self);
}

- (void)_updateCornerMask {
    if (enableSharpener && enableCustomRadius && isStandardAppWindow(self)) {
        applyCornerRadiusToWindow(self);
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void);
#pragma clang diagnostic pop
    }
}

- (void)_setCornerRadius:(CGFloat)radius {
    if (!enableSharpener || !enableCustomRadius || !isStandardAppWindow(self)) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void, radius);
#pragma clang diagnostic pop
        return;
    }

    if (customRadius == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void, 0);
#pragma clang diagnostic pop
        return;
    }

    CGFloat r = (self.styleMask & NSWindowStyleMaskFullScreen) ? 0 : customRadius;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, r);
#pragma clang diagnostic pop
}

- (id)_cornerMask {
    if (enableSharpener && customRadius == 0 && isStandardAppWindow(self)) {
        // Create a 1x1 white image for square corners
        NSImage *squareCornerMask = [[NSImage alloc] initWithSize:NSMakeSize(1, 1)];
        [squareCornerMask lockFocus];
        [[NSColor whiteColor] set];
        NSRectFill(NSMakeRect(0, 0, 1, 1));
        [squareCornerMask unlockFocus];
        return squareCornerMask;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    return ZKOrig(id);
#pragma clang diagnostic pop
}

- (void)toggleFullScreen:(id)sender {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, sender);
#pragma clang diagnostic pop
}

@end
