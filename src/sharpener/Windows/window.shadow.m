#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import "window.h"
#import "window_filter.h"
#import "ZKSwizzle.h"

#pragma mark - Red Frame Window

@interface RedFrameWindow : NSWindow
@property (nonatomic, weak) NSWindow *targetWindow;
@end

@implementation RedFrameWindow

- (instancetype)initWithContentRect:(NSRect)contentRect targetWindow:(NSWindow *)targetWindow {
    if ((self = [super initWithContentRect:contentRect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO])) {
        _targetWindow = targetWindow;
        // Default to blue (inactive), will be updated based on focus state
        self.backgroundColor = [NSColor blueColor];
        self.opaque = YES;
        self.hasShadow = NO;
        self.alphaValue = 1.0;
        self.level = targetWindow.level;
        self.ignoresMouseEvents = YES;
        self.collectionBehavior = NSWindowCollectionBehaviorIgnoresCycle | NSWindowCollectionBehaviorStationary;
        
        NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, contentRect.size.width, contentRect.size.height)];
        contentView.wantsLayer = YES;
        // Default to blue (inactive), will be updated based on focus state
        contentView.layer.backgroundColor = [[NSColor blueColor] CGColor];
        self.contentView = contentView;
    }
    return self;
}

- (void)updateColorForFocusState {
    BOOL isActive = self.targetWindow.isKeyWindow || self.targetWindow.isMainWindow;
    NSColor *color = isActive ? [NSColor redColor] : [NSColor blueColor];
    self.backgroundColor = color;
    if (self.contentView && self.contentView.layer) {
        self.contentView.layer.backgroundColor = [color CGColor];
    }
}

- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen { return frameRect; }

- (BOOL)shouldHideForFullscreen {
    if (!self.targetWindow) return NO;
    // Check style mask
    if ((self.targetWindow.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen) {
        return YES;
    }
    // Check if window frame matches screen frame (likely fullscreen)
    @try {
        NSScreen *screen = self.targetWindow.screen ?: [NSScreen mainScreen];
        if (screen) {
            NSRect screenFrame = screen.frame;
            NSRect windowFrame = self.targetWindow.frame;
            // Allow small tolerance for menu bar
            if (fabs(windowFrame.origin.x - screenFrame.origin.x) < 1 &&
                fabs(windowFrame.origin.y - screenFrame.origin.y) < 1 &&
                fabs(windowFrame.size.width - screenFrame.size.width) < 1 &&
                fabs(windowFrame.size.height - screenFrame.size.height) < 1) {
                return YES;
            }
        }
    } @catch (NSException *e) {}
    return NO;
}

- (void)orderFront:(id)sender {
    // Don't show if parent window is fullscreen
    if ([self shouldHideForFullscreen]) {
        return;
    }
    [super orderFront:sender];
}

- (void)orderBack:(id)sender {
    // Don't show if parent window is fullscreen
    if ([self shouldHideForFullscreen]) {
        return;
    }
    [super orderBack:sender];
}

@end

#pragma mark - Window Tracking

static NSMapTable<NSWindow *, NSWindow *> *windowToRedFrameMap = nil;
static NSHashTable<NSWindow *> *windowsInFullscreenTransition = nil;

static inline void initializeWindowTracking(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        windowToRedFrameMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory valueOptions:NSPointerFunctionsStrongMemory];
        windowsInFullscreenTransition = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory];
    });
}

static inline BOOL isWindowInFullscreenTransition(NSWindow *window) {
    if (!window) return NO;
    initializeWindowTracking();
    return [windowsInFullscreenTransition containsObject:window];
}

static inline NSRect calculateRedFrameRect(NSRect windowFrame) {
    return NSMakeRect(windowFrame.origin.x - 10, windowFrame.origin.y - 10, windowFrame.size.width + 20, windowFrame.size.height + 20);
}

// Window filtering functions are defined in window_filter.h

static inline void attachRedFrame(NSWindow *redFrame, NSWindow *parent) {
    if (!redFrame || !parent) return;
    
    // Handle fullscreen windows
    if (isWindowFullscreen(parent) || isWindowInFullscreenTransition(parent)) {
        if (redFrame.isVisible) {
            [redFrame orderOut:nil];
        }
        if (redFrame.parentWindow == parent) {
            [parent removeChildWindow:redFrame];
        }
        return;
    }
    
    // Attach red frame as child window below parent
    // Using NSWindowBelow ensures it stays behind parent automatically
    if (!redFrame.parentWindow) {
        [parent addChildWindow:redFrame ordered:NSWindowBelow];
    }
    // Always sync level to maintain proper z-ordering
    redFrame.level = parent.level;
}


static NSWindow *getOrCreateRedFrameForWindow(NSWindow *window) {
    if (!window) return nil;
    
    if (![NSThread isMainThread]) {
        __block NSWindow *result = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = getOrCreateRedFrameForWindow(window);
        });
        return result;
    }
    
    initializeWindowTracking();
    
    @try {
        BOOL isFullscreen = isWindowFullscreen(window) || isWindowInFullscreenTransition(window);
        if (![window isKindOfClass:[NSWindow class]] || !window.isVisible || isFullscreen) {
            return nil;
        }
        
        NSWindow *existing = [windowToRedFrameMap objectForKey:window];
        if (existing) {
            if (!existing.isVisible) {
                [existing setFrame:calculateRedFrameRect(window.frame) display:NO];
                existing.alphaValue = 1.0;
                attachRedFrame(existing, window);
                // Update color based on focus state
                if ([existing isKindOfClass:[RedFrameWindow class]]) {
                    [(RedFrameWindow *)existing updateColorForFocusState];
                }
            }
            return existing.isVisible ? existing : nil;
        }
        
        NSRect windowFrame = window.frame;
        if (windowFrame.size.width <= 0 || windowFrame.size.height <= 0) {
            return nil;
        }
        
        NSRect redFrameRect = calculateRedFrameRect(windowFrame);
        RedFrameWindow *redFrame = [[RedFrameWindow alloc] initWithContentRect:redFrameRect targetWindow:window];
        if (!redFrame) {
            return nil;
        }
        
        [windowToRedFrameMap setObject:redFrame forKey:window];
        attachRedFrame(redFrame, window);
        // Set initial color based on focus state
        [redFrame updateColorForFocusState];
        return redFrame;
    } @catch (NSException *e) {
        return nil;
    }
}

static void updateRedFrameForWindow(NSWindow *window) {
    if (!window || !window.isVisible) return;
    
    @try {
        initializeWindowTracking();
        
        // Handle fullscreen windows
        BOOL isFullscreen = isWindowFullscreen(window) || isWindowInFullscreenTransition(window);
        if (isFullscreen) {
            NSWindow *redFrame = [windowToRedFrameMap objectForKey:window];
            if (redFrame) {
                if (redFrame.isVisible) {
                    [redFrame orderOut:nil];
                }
                if (redFrame.parentWindow == window) {
                    [window removeChildWindow:redFrame];
                }
            }
            return;
        }
        
        NSWindow *redFrame = [windowToRedFrameMap objectForKey:window];
        if (redFrame && redFrame.isVisible) {
            // Update existing red frame frame and level
            NSRect newRect = calculateRedFrameRect(window.frame);
            [redFrame setFrame:newRect display:NO];
            redFrame.level = window.level;
            
            // Update color based on focus state
            if ([redFrame isKindOfClass:[RedFrameWindow class]]) {
                [(RedFrameWindow *)redFrame updateColorForFocusState];
            }
            
            // Ensure red frame is properly attached
            if (!redFrame.parentWindow) {
                attachRedFrame(redFrame, window);
            }
        } else if (isStandardAppWindow(window)) {
            // Create new red frame for standard windows
            getOrCreateRedFrameForWindow(window);
        }
    } @catch (NSException *e) {}
}

#pragma mark - Swizzled NSWindow

ZKSwizzleInterfaceGroup(AS_NSWindow_RedFrame, NSWindow, NSWindow, APPLE_SHARPENER)
@implementation AS_NSWindow_RedFrame
- (void)setFrame:(NSRect)frameRect display:(BOOL)flag {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, frameRect, flag);
#pragma clang diagnostic pop
    // Update red frame instantly during resize/move (skip during fullscreen transitions)
    if (![self isKindOfClass:[RedFrameWindow class]] && 
        !isWindowFullscreen(self) && 
        !isWindowInFullscreenTransition(self)) {
        initializeWindowTracking();
        NSWindow *redFrame = [windowToRedFrameMap objectForKey:self];
        if (redFrame && redFrame.isVisible) {
            // Update frame immediately for instant resize/move
            NSRect newRect = calculateRedFrameRect(frameRect);
            [redFrame setFrame:newRect display:flag];
            // Sync level to maintain proper z-ordering
            redFrame.level = self.level;
        } else if (isStandardAppWindow(self)) {
            // Create red frame if it doesn't exist
            updateRedFrameForWindow(self);
        }
    }
}

- (void)orderFront:(id)sender {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, sender);
#pragma clang diagnostic pop
    // Ensure red frame stays behind when window is brought to front
    if (![self isKindOfClass:[RedFrameWindow class]] && 
        !isWindowFullscreen(self) && 
        !isWindowInFullscreenTransition(self)) {
        initializeWindowTracking();
        NSWindow *redFrame = [windowToRedFrameMap objectForKey:self];
        if (redFrame && redFrame.isVisible) {
            redFrame.level = self.level;
            // Update color based on focus state
            if ([redFrame isKindOfClass:[RedFrameWindow class]]) {
                [(RedFrameWindow *)redFrame updateColorForFocusState];
            }
            // Ensure red frame is attached and stays behind
            if (redFrame.parentWindow != self) {
                attachRedFrame(redFrame, self);
            }
        }
    }
}

- (void)makeKeyAndOrderFront:(id)sender {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, sender);
#pragma clang diagnostic pop
    // Ensure red frame stays behind when window becomes key
    if (![self isKindOfClass:[RedFrameWindow class]] && 
        !isWindowFullscreen(self) && 
        !isWindowInFullscreenTransition(self)) {
        initializeWindowTracking();
        NSWindow *redFrame = [windowToRedFrameMap objectForKey:self];
        if (redFrame && redFrame.isVisible) {
            redFrame.level = self.level;
            // Update color based on focus state (window is now key)
            if ([redFrame isKindOfClass:[RedFrameWindow class]]) {
                [(RedFrameWindow *)redFrame updateColorForFocusState];
            }
            if (redFrame.parentWindow != self) {
                attachRedFrame(redFrame, self);
            }
        } else if (isStandardAppWindow(self)) {
            updateRedFrameForWindow(self);
        }
    }
}
@end

ZKSwizzleInterfaceGroup(AS_NSWindow_Shadow, NSWindow, NSWindow, APPLE_SHARPENER)
@implementation AS_NSWindow_Shadow
- (void)setHasShadow:(BOOL)hasShadow {
    // Global tweak applies to all windows
    BOOL shouldDisable = ![self isKindOfClass:[RedFrameWindow class]] && isStandardAppWindow(self);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
    ZKOrig(void, shouldDisable ? NO : hasShadow);
#pragma clang diagnostic pop
}
@end

#pragma mark - Public API

void disableWindowShadowViaAppKit(NSWindow *window) {
    if (!window) return;
    
    // Global tweak applies to all standard windows
    if (!isStandardAppWindow(window)) {
        return;
    }
    
    @try {
        window.hasShadow = NO;
        if ([window respondsToSelector:@selector(setShadow:)]) {
            [window performSelector:@selector(setShadow:) withObject:nil];
        }
    } @catch (NSException *e) {}
}

void createRedFrameForWindow(NSWindow *window) {
    if (!window) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            createRedFrameForWindow(window);
        });
        return;
    }
    @try {
        // Global tweak applies to all standard windows
        if (isStandardAppWindow(window) && window.isVisible && !isWindowFullscreen(window) && !isWindowInFullscreenTransition(window)) {
            getOrCreateRedFrameForWindow(window);
        }
    } @catch (NSException *e) {}
}

#pragma mark - Notifications

static void setupRedFrameNotifications(void) __attribute__((constructor));
static void setupRedFrameNotifications(void) {
    @try {
        // Check if AppKit classes are available
        if (!NSClassFromString(@"NSApplication") || !NSClassFromString(@"NSWindow")) return;
        
        // Safely initialize window tracking
        @try {
            initializeWindowTracking();
        } @catch (NSException *e) {
            return; // Can't initialize, abort
        }
        
        // Safely get notification center and main queue
        NSNotificationCenter *center = nil;
        NSOperationQueue *mainQueue = nil;
        @try {
            center = [NSNotificationCenter defaultCenter];
            mainQueue = [NSOperationQueue mainQueue];
            if (!center || !mainQueue) return;
        } @catch (NSException *e) {
            return; // AppKit not ready, abort silently
        }
        
        // Window creation notifications - handled via focus notifications
        // No separate handler needed as focus notifications cover window creation
        
        // Focus change notifications - update red frame color
        // Use weak reference to avoid retain cycles (prevents Zoom memory leaks)
        void (^focusHandler)(NSNotification *) = ^(NSNotification *note) {
            @autoreleasepool {
                NSWindow *window = note.object;
                if (!window || ![window isKindOfClass:[NSWindow class]] || [window isKindOfClass:[RedFrameWindow class]]) {
                    return;
                }
                // Validate window is still valid
                @try {
                    (void)window.isVisible;
                } @catch (NSException *e) {
                    return; // Window deallocated
                }
                initializeWindowTracking();
                NSWindow *redFrame = [windowToRedFrameMap objectForKey:window];
                if (redFrame && [redFrame isKindOfClass:[RedFrameWindow class]]) {
                    @try {
                        [(RedFrameWindow *)redFrame updateColorForFocusState];
                    } @catch (NSException *e) {
                        // Ignore exceptions
                    }
                }
            }
        };
        
        [center addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:mainQueue usingBlock:focusHandler];
        [center addObserverForName:NSWindowDidResignKeyNotification object:nil queue:mainQueue usingBlock:focusHandler];
        [center addObserverForName:NSWindowDidBecomeMainNotification object:nil queue:mainQueue usingBlock:focusHandler];
        [center addObserverForName:NSWindowDidResignMainNotification object:nil queue:mainQueue usingBlock:focusHandler];
        
        // Window resize notification - update red frame instantly
        // Use weak reference and autoreleasepool to prevent memory leaks
        void (^resizeHandler)(NSNotification *) = ^(NSNotification *note) {
            @autoreleasepool {
                NSWindow *window = note.object;
                if (!window || ![window isKindOfClass:[NSWindow class]] || [window isKindOfClass:[RedFrameWindow class]]) {
                    return;
                }
                // Validate window is still valid
                @try {
                    if (isWindowFullscreen(window) || isWindowInFullscreenTransition(window)) {
                        return;
                    }
                    (void)window.frame; // Validate window
                } @catch (NSException *e) {
                    return; // Window deallocated
                }
                initializeWindowTracking();
                NSWindow *redFrame = [windowToRedFrameMap objectForKey:window];
                if (redFrame && redFrame.isVisible) {
                    @try {
                        NSRect newRect = calculateRedFrameRect(window.frame);
                        [redFrame setFrame:newRect display:YES];
                        redFrame.level = window.level;
                    } @catch (NSException *e) {
                        // Ignore exceptions
                    }
                } else {
                    updateRedFrameForWindow(window);
                }
            }
        };
        
        // Window move notification - update red frame instantly
        // Use weak reference and autoreleasepool to prevent memory leaks
        void (^moveHandler)(NSNotification *) = ^(NSNotification *note) {
            @autoreleasepool {
                NSWindow *window = note.object;
                if (!window || ![window isKindOfClass:[NSWindow class]] || [window isKindOfClass:[RedFrameWindow class]]) {
                    return;
                }
                // Validate window is still valid
                @try {
                    if (isWindowFullscreen(window) || isWindowInFullscreenTransition(window)) {
                        return;
                    }
                    (void)window.frame; // Validate window
                } @catch (NSException *e) {
                    return; // Window deallocated
                }
                initializeWindowTracking();
                NSWindow *redFrame = [windowToRedFrameMap objectForKey:window];
                if (redFrame && redFrame.isVisible) {
                    @try {
                        NSRect newRect = calculateRedFrameRect(window.frame);
                        [redFrame setFrame:newRect display:YES];
                        redFrame.level = window.level;
                    } @catch (NSException *e) {
                        // Ignore exceptions
                    }
                } else {
                    updateRedFrameForWindow(window);
                }
            }
        };
        
        [center addObserverForName:NSWindowDidResizeNotification object:nil queue:mainQueue usingBlock:resizeHandler];
        [center addObserverForName:NSWindowDidMoveNotification object:nil queue:mainQueue usingBlock:moveHandler];
        
        // Fullscreen notifications
        [center addObserverForName:NSWindowWillEnterFullScreenNotification object:nil queue:mainQueue usingBlock:^(NSNotification *note) {
            @autoreleasepool {
                NSWindow *window = note.object;
                if (!window || ![window isKindOfClass:[NSWindow class]]) {
                    return;
                }
                @try {
                    (void)window.isVisible;
                } @catch (NSException *e) {
                    return;
                }
                initializeWindowTracking();
                [windowsInFullscreenTransition addObject:window];
                NSWindow *redFrame = [windowToRedFrameMap objectForKey:window];
                if (redFrame && redFrame.isVisible) {
                    @try {
                        [redFrame orderOut:nil];
                    } @catch (NSException *e) {
                        // Ignore
                    }
                }
            }
        }];
        
        [center addObserverForName:NSWindowDidEnterFullScreenNotification object:nil queue:mainQueue usingBlock:^(NSNotification *note) {
            @autoreleasepool {
                NSWindow *window = note.object;
                if (!window || ![window isKindOfClass:[NSWindow class]]) {
                    return;
                }
                @try {
                    (void)window.isVisible;
                } @catch (NSException *e) {
                    return;
                }
                initializeWindowTracking();
                [windowsInFullscreenTransition removeObject:window];
                NSWindow *redFrame = [windowToRedFrameMap objectForKey:window];
                if (redFrame) {
                    @try {
                        if (redFrame.isVisible) {
                            [redFrame orderOut:nil];
                        }
                        if (redFrame.parentWindow == window) {
                            [window removeChildWindow:redFrame];
                        }
                        redFrame.alphaValue = 0.0;
                    } @catch (NSException *e) {
                        // Ignore
                    }
                }
            }
        }];
        
        [center addObserverForName:NSWindowWillExitFullScreenNotification object:nil queue:mainQueue usingBlock:^(NSNotification *note) {
            @autoreleasepool {
                NSWindow *window = note.object;
                if (!window || ![window isKindOfClass:[NSWindow class]]) {
                    return;
                }
                @try {
                    (void)window.isVisible;
                } @catch (NSException *e) {
                    return;
                }
                initializeWindowTracking();
                [windowsInFullscreenTransition addObject:window];
            }
        }];
        
        [center addObserverForName:NSWindowDidExitFullScreenNotification object:nil queue:mainQueue usingBlock:^(NSNotification *note) {
            @autoreleasepool {
                NSWindow *window = note.object;
                if (!window || ![window isKindOfClass:[NSWindow class]]) {
                    return;
                }
                // Validate window is still valid
                @try {
                    (void)window.isVisible;
                } @catch (NSException *e) {
                    return; // Window deallocated
                }
                initializeWindowTracking();
                [windowsInFullscreenTransition removeObject:window];
                if (isStandardAppWindow(window) && window.isVisible) {
                    // Use weak reference pattern to avoid retaining window in dispatch_after
                    NSWindow *weakWindow = window;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        @autoreleasepool {
                            @try {
                                // Validate window is still valid
                                if (!weakWindow || ![weakWindow isKindOfClass:[NSWindow class]]) {
                                    return;
                                }
                                (void)weakWindow.isVisible;
                                if (!isWindowFullscreen(weakWindow) && !isWindowInFullscreenTransition(weakWindow)) {
                                    createRedFrameForWindow(weakWindow);
                                }
                            } @catch (NSException *e) {
                                // Window deallocated or invalid
                            }
                        }
                    });
                }
            }
        }];
        
        // Window cleanup - ensure proper cleanup to prevent memory leaks
        [center addObserverForName:NSWindowWillCloseNotification object:nil queue:mainQueue usingBlock:^(NSNotification *note) {
            @autoreleasepool {
                NSWindow *window = note.object;
                if (!window || ![window isKindOfClass:[NSWindow class]]) {
                    return;
                }
                initializeWindowTracking();
                NSWindow *redFrame = [windowToRedFrameMap objectForKey:window];
                if (redFrame) {
                    @try {
                        if (redFrame.parentWindow == window) {
                            [window removeChildWindow:redFrame];
                        }
                        [redFrame close];
                        // Remove from map to prevent leaks
                        [windowToRedFrameMap removeObjectForKey:window];
                    } @catch (NSException *e) {
                        // Ignore exceptions but still try to remove from map
                        @try {
                            [windowToRedFrameMap removeObjectForKey:window];
                        } @catch (NSException *e2) {}
                    }
                }
            }
        }];
    } @catch (NSException *e) {
        // Ignore exceptions during notification setup
    }
}
