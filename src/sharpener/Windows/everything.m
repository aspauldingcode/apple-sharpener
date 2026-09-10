#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "ZKSwizzle.h"
#import <notify.h>
#import "sharpener_log.h"

/**
 * Window sharpening implementation for apple-sharpener
 * Disables all macOS window corner radius by intercepting CALayer masks
 * and setting masksToBounds to false.
 */

#pragma mark - Global State

static BOOL enableSharpener = YES;

#pragma mark - Forward Declarations

void toggleSquareCorners(BOOL enable, NSInteger __unused radius);
static void setupWindowNotifications(void) __attribute__((constructor));
static CALayer *findRootCALayer(NSWindow *window);
static BOOL isWindowLayer(CALayer *layer);

#pragma mark - Helper Functions

// Check if we should log (only for GUI apps, not terminal/CLI apps)
static inline BOOL shouldLog(void) {
    static BOOL cachedValue = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BOOL isTerminal = isatty(STDIN_FILENO) || isatty(STDOUT_FILENO) || isatty(STDERR_FILENO);
        if (isTerminal) {
            cachedValue = NO;
            return;
        }
        
        @try {
            BOOL hasGUIApp = (NSClassFromString(@"NSApplication") != nil && [NSApplication sharedApplication] != nil);
            cachedValue = hasGUIApp;
        } @catch (NSException *exception) {
            cachedValue = NO;
        }
    });
    return cachedValue;
}

// Find the root CALayer for a window
static CALayer *findRootCALayer(NSWindow *window) {
    if (!window) return nil;
    
    @try {
        // Try _backingLayer first (most direct)
        id backingLayer = [window valueForKey:@"_backingLayer"];
        if (backingLayer && [backingLayer isKindOfClass:[CALayer class]]) {
            CALayer *rootLayer = (CALayer *)backingLayer;
            while (rootLayer.superlayer) {
                rootLayer = rootLayer.superlayer;
            }
            return rootLayer;
        }
        
        // Try contentView's layer hierarchy
        NSView *contentView = window.contentView;
        if (contentView) {
            [contentView setWantsLayer:YES];
            CALayer *layer = contentView.layer;
            if (!layer) {
                [contentView setNeedsDisplay:YES];
                [contentView displayIfNeeded];
                layer = contentView.layer;
            }
            
            if (layer) {
                CALayer *rootLayer = layer;
                while (rootLayer.superlayer) {
                    rootLayer = rootLayer.superlayer;
                }
                return rootLayer;
            }
        }
        
        // Try window's layer property directly
        if ([window respondsToSelector:@selector(layer)]) {
            CALayer *layer = [window performSelector:@selector(layer)];
            if (layer && [layer isKindOfClass:[CALayer class]]) {
                while (layer.superlayer) {
                    layer = layer.superlayer;
                }
                return layer;
            }
        }
    } @catch (NSException *exception) {
        // Ignore - window might not support these properties
    }
    
    return nil;
}

// Check if a CALayer belongs to a window
static BOOL isWindowLayer(CALayer *layer) {
    if (!layer || !enableSharpener) return NO;
    
    @try {
        // Check if this layer is connected to a window through delegate
        if ([layer respondsToSelector:@selector(delegate)]) {
            id delegate = [(id)layer delegate];
            if ([delegate isKindOfClass:[NSView class]]) {
                NSView *view = (NSView *)delegate;
                NSWindow *window = view.window;
                if (window) {
                    return YES;
                }
            }
        }
        
        // Check if this layer is a window's backing layer
        if ([layer respondsToSelector:@selector(valueForKey:)]) {
            id windowRef = [(id)layer valueForKey:@"_window"];
            if (windowRef && [windowRef isKindOfClass:[NSWindow class]]) {
                return YES;
            }
        }
        
        // Traverse up to find window connection
        CALayer *currentLayer = layer;
        NSInteger depth = 0;
        while (currentLayer && depth < 20) {
            if ([currentLayer respondsToSelector:@selector(delegate)]) {
                id delegate = [(id)currentLayer delegate];
                if ([delegate isKindOfClass:[NSView class]]) {
                    NSView *view = (NSView *)delegate;
                    NSWindow *window = view.window;
                    if (window) {
                        return YES;
                    }
                }
            }
            currentLayer = currentLayer.superlayer;
            depth++;
        }
    } @catch (NSException *exception) {
        // Ignore
    }
    
    return NO;
}

// Disable corner radius for a window by modifying its root layer
static void disableWindowCornerRadius(NSWindow *window) {
    if (!window || !enableSharpener) return;
    
    @try {
        CALayer *rootLayer = findRootCALayer(window);
        if (rootLayer) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            
            // Set corner radius to 0
            rootLayer.cornerRadius = 0;
            
            // Set masksToBounds to NO (false) - this is key!
            rootLayer.masksToBounds = NO;
            
            // Remove any existing mask
            rootLayer.mask = nil;
            
            [CATransaction commit];
            
            if (shouldLog()) {
                NSString *windowTitle = window.title ?: @"(untitled)";
                NSString *appName = [[NSProcessInfo processInfo] processName] ?: @"unknown";
                SHARPENER_LOG(@"Windows: Disabled corner radius for \"%@\" (%@)", windowTitle, appName);
            }
        }
    } @catch (NSException *exception) {
        // Fail silently
    }
}

#pragma mark - Public API

void toggleSquareCorners(BOOL enable, NSInteger __unused radius) {
    BOOL stateChanged = (enableSharpener != enable);
    enableSharpener = enable;
    
    if (stateChanged) {
        @try {
            NSApplication *app = [NSApplication sharedApplication];
            for (NSWindow *window in app.windows) {
                if (enableSharpener) {
                    disableWindowCornerRadius(window);
                }
            }
        } @catch (NSException *exception) {
            // Silently fail if we can't access NSApplication
        }
    }
}

#pragma mark - Notification Setup

static void setupWindowNotifications(void) {
    ZKSwizzleGroup(APPLE_SHARPENER);
    
    dispatch_queue_t queue = dispatch_get_main_queue();
    
    static const char *kNotifyEnabled = "com.aspauldingcode.apple_sharpener.enabled";
    static const char *kNotifyWindowsEnabled = "com.aspauldingcode.apple_sharpener.windows.enabled";
    
    // Load persisted state from NSUserDefaults
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.aspauldingcode.apple_sharpener"];
    if ([defaults objectForKey:@"windows_enabled"] != nil) {
        enableSharpener = [defaults boolForKey:@"windows_enabled"];
    } else {
        enableSharpener = [defaults boolForKey:@"enabled"];
    }
    
    // Add observers for window events
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeMainNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
        @try {
            disableWindowCornerRadius(notification.object);
        } @catch (NSException *exception) {
            // Ignore
        }
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
        @try {
            disableWindowCornerRadius(notification.object);
        } @catch (NSException *exception) {
            // Ignore
        }
    }];
    
    if (shouldLog()) {
        SHARPENER_LOG(@"Windows: Loaded enableSharpener: %d", enableSharpener);
    }
    
    toggleSquareCorners(enableSharpener, 0);
    
    int tokenEnable = 0;
    notify_register_dispatch("com.aspauldingcode.apple_sharpener.enable", &tokenEnable, queue, ^(int __unused t){
        toggleSquareCorners(YES, 0);
        [defaults setBool:YES forKey:@"enabled"];
        [defaults synchronize];
    });
    
    int tokenDisable = 0;
    notify_register_dispatch("com.aspauldingcode.apple_sharpener.disable", &tokenDisable, queue, ^(int __unused t){
        toggleSquareCorners(NO, 0);
        [defaults setBool:NO forKey:@"enabled"];
        [defaults synchronize];
    });
    
    int tokenToggle = 0;
    notify_register_dispatch("com.aspauldingcode.apple_sharpener.toggle", &tokenToggle, queue, ^(int __unused t){
        toggleSquareCorners(!enableSharpener, 0);
        [defaults setBool:enableSharpener forKey:@"enabled"];
        [defaults synchronize];
    });
    
    int tokenEnabled = 0;
    notify_register_dispatch(kNotifyEnabled, &tokenEnabled, queue, ^(int token) {
        uint64_t state;
        notify_get_state(token, &state);
        BOOL globalEnabled = (state != 0);
        if ([defaults objectForKey:@"windows_enabled"] == nil) {
            enableSharpener = globalEnabled;
        }
        [defaults setBool:globalEnabled forKey:@"enabled"];
        [defaults synchronize];
        toggleSquareCorners(enableSharpener, 0);
    });
    
    int tokenWindowsEnabled = 0;
    notify_register_dispatch(kNotifyWindowsEnabled, &tokenWindowsEnabled, queue, ^(int token) {
        uint64_t state;
        notify_get_state(token, &state);
        BOOL windowsEnabled = (state != 0);
        enableSharpener = windowsEnabled;
        [defaults setBool:windowsEnabled forKey:@"windows_enabled"];
        [defaults synchronize];
        toggleSquareCorners(enableSharpener, 0);
    });
}

#pragma mark - Swizzled NSWindow

ZKSwizzleInterfaceGroup(AS_NSWindow_CornerRadius, NSWindow, NSWindow, APPLE_SHARPENER)
@implementation AS_NSWindow_CornerRadius

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backingStoreType defer:(BOOL)flag {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    id result = ZKOrig(id, contentRect, style, backingStoreType, flag);
#pragma clang diagnostic pop
    
    if (enableSharpener) {
        NSWindow *window = (NSWindow *)result;
        dispatch_async(dispatch_get_main_queue(), ^{
            disableWindowCornerRadius(window);
        });
    }
    return result;
}
#pragma clang diagnostic pop

- (void)setFrame:(NSRect)frameRect display:(BOOL)flag {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, frameRect, flag);
#pragma clang diagnostic pop
    if (enableSharpener) {
        disableWindowCornerRadius(self);
    }
}

- (void)_updateCornerMask {
    if (enableSharpener) {
        disableWindowCornerRadius(self);
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void);
#pragma clang diagnostic pop
    }
}

- (void)_setCornerRadius:(CGFloat)radius {
    if (!enableSharpener) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void, radius);
#pragma clang diagnostic pop
        return;
    }
    
    // Force corner radius to 0
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, 0);
#pragma clang diagnostic pop
    
    disableWindowCornerRadius(self);
}

- (void)makeKeyAndOrderFront:(id)sender {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, sender);
#pragma clang diagnostic pop
    if (enableSharpener) {
        disableWindowCornerRadius(self);
    }
}

- (void)orderFront:(id)sender {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, sender);
#pragma clang diagnostic pop
    if (enableSharpener) {
        disableWindowCornerRadius(self);
    }
}

- (void)setContentView:(NSView *)contentView {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, contentView);
#pragma clang diagnostic pop
    if (enableSharpener) {
        dispatch_async(dispatch_get_main_queue(), ^{
            disableWindowCornerRadius(self);
        });
    }
}

@end

#pragma mark - Swizzled NSPanel

ZKSwizzleInterfaceGroup(AS_NSPanel_CornerRadius, NSPanel, NSWindow, APPLE_SHARPENER)
@implementation AS_NSPanel_CornerRadius

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backingStoreType defer:(BOOL)flag {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    id result = ZKOrig(id, contentRect, style, backingStoreType, flag);
#pragma clang diagnostic pop
    
    if (enableSharpener) {
        NSWindow *window = (NSWindow *)result;
        dispatch_async(dispatch_get_main_queue(), ^{
            disableWindowCornerRadius(window);
        });
    }
    return result;
}
#pragma clang diagnostic pop

- (void)setFrame:(NSRect)frameRect display:(BOOL)flag {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, frameRect, flag);
#pragma clang diagnostic pop
    if (enableSharpener) {
        disableWindowCornerRadius(self);
    }
}

- (void)_updateCornerMask {
    if (enableSharpener) {
        disableWindowCornerRadius(self);
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void);
#pragma clang diagnostic pop
    }
}

- (void)_setCornerRadius:(CGFloat)radius {
    if (!enableSharpener) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void, radius);
#pragma clang diagnostic pop
        return;
    }
    
    // Force corner radius to 0
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, 0);
#pragma clang diagnostic pop
    
    disableWindowCornerRadius(self);
}

- (void)makeKeyAndOrderFront:(id)sender {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, sender);
#pragma clang diagnostic pop
    if (enableSharpener) {
        disableWindowCornerRadius(self);
    }
}

- (void)orderFront:(id)sender {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, sender);
#pragma clang diagnostic pop
    if (enableSharpener) {
        disableWindowCornerRadius(self);
    }
}

- (void)setContentView:(NSView *)contentView {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, contentView);
#pragma clang diagnostic pop
    if (enableSharpener) {
        dispatch_async(dispatch_get_main_queue(), ^{
            disableWindowCornerRadius(self);
        });
    }
}

@end

#pragma mark - Swizzled NSApplication

ZKSwizzleInterfaceGroup(AS_NSApplication_CornerRadius, NSApplication, NSApplication, APPLE_SHARPENER)
@implementation AS_NSApplication_CornerRadius

- (void)addWindowsItem:(NSWindow *)window title:(NSString *)title filename:(BOOL)isFilename {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, window, title, isFilename);
#pragma clang diagnostic pop
    if (enableSharpener && window) {
        dispatch_async(dispatch_get_main_queue(), ^{
            disableWindowCornerRadius(window);
        });
    }
}

- (void)updateWindows {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void);
#pragma clang diagnostic pop
    if (enableSharpener) {
        @try {
            for (NSWindow *window in self.windows) {
                disableWindowCornerRadius(window);
            }
        } @catch (NSException *exception) {
            // Ignore
        }
    }
}

- (void)finishLaunching {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void);
#pragma clang diagnostic pop
    if (enableSharpener) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                for (NSWindow *window in self.windows) {
                    disableWindowCornerRadius(window);
                }
            } @catch (NSException *exception) {
                // Ignore
            }
        });
    }
}

- (void)activateIgnoringOtherApps:(BOOL)flag {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, flag);
#pragma clang diagnostic pop
    if (enableSharpener) {
        @try {
            for (NSWindow *window in self.windows) {
                disableWindowCornerRadius(window);
            }
        } @catch (NSException *exception) {
            // Ignore
        }
    }
}

- (NSModalResponse)runModalForWindow:(NSWindow *)window {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    NSModalResponse response = ZKOrig(NSModalResponse, window);
#pragma clang diagnostic pop
    if (enableSharpener && window) {
        disableWindowCornerRadius(window);
    }
    return response;
}

- (void)beginSheet:(NSWindow *)sheetWindow completionHandler:(void (^)(NSModalResponse returnCode))handler {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, sheetWindow, handler);
#pragma clang diagnostic pop
    if (enableSharpener && sheetWindow) {
        dispatch_async(dispatch_get_main_queue(), ^{
            disableWindowCornerRadius(sheetWindow);
        });
    }
}

@end

#pragma mark - Swizzled CALayer

ZKSwizzleInterfaceGroup(AS_CALayer_CornerRadius, CALayer, CALayer, APPLE_SHARPENER)
@implementation AS_CALayer_CornerRadius

- (void)setCornerRadius:(CGFloat)cornerRadius {
    // If sharpener is enabled and this is a window layer, force corner radius to 0
    if (enableSharpener && isWindowLayer(self)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void, 0);
#pragma clang diagnostic pop
        self.masksToBounds = NO;  // Set to NO (false) as requested
        self.mask = nil;  // Remove any existing mask
        [CATransaction commit];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void, cornerRadius);
#pragma clang diagnostic pop
    }
}

- (void)setMasksToBounds:(BOOL)masksToBounds {
    // If sharpener is enabled and this is a window layer, always set masksToBounds to NO
    if (enableSharpener && isWindowLayer(self)) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void, NO);  // Force to NO (false)
#pragma clang diagnostic pop
        // Also ensure corner radius is 0
        if (self.cornerRadius > 0) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.cornerRadius = 0;
            [CATransaction commit];
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void, masksToBounds);
#pragma clang diagnostic pop
    }
}

- (void)setMask:(CALayer *)mask {
    // If sharpener is enabled and this is a window layer, prevent mask from being set
    if (enableSharpener && isWindowLayer(self)) {
        // Don't set the mask - this prevents default macOS mask from being applied
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void, nil);  // Always set to nil to disable mask
#pragma clang diagnostic pop
        [CATransaction commit];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
        ZKOrig(void, mask);
#pragma clang diagnostic pop
    }
}

- (void)layoutSublayers {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void);
#pragma clang diagnostic pop
    
    // After layout, ensure corner radius is 0 and masksToBounds is NO for window layers
    if (enableSharpener && isWindowLayer(self)) {
        if (self.cornerRadius > 0 || self.masksToBounds != NO) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.cornerRadius = 0;
            self.masksToBounds = NO;  // Set to NO (false)
            self.mask = nil;
            [CATransaction commit];
        }
    }
}

@end

