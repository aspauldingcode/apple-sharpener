/**
 * Apple Sharpener: Window Chrome Roles
 *
 * Defines structures and functions to identify specific AppKit chrome
 * components (traffic lights, toolbar, sidebar) within the view and layer
 * hierarchies. This allows the sharpener to apply targeted modifications
 * based on the context of a view.
 */

#ifndef WINDOW_CHROME_ROLES_H
#define WINDOW_CHROME_ROLES_H

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

@class NSView;
@class NSWindow;

/// Describes which AppKit “subchrome” buckets a view or layer participates in.
/// Used to map Settings (traffic / toolbar / sidebar) onto CALayer swizzles.
typedef struct {
  BOOL trafficLight;
  BOOL toolbarTitlebar;
  BOOL sidebar;
} SharpenerChromeFlags;

void SharpenerChromeFlagsReset(SharpenerChromeFlags *_Nullable flags);

/// Walks the superview chain from `view` and sets flags.
void SharpenerMergeChromeFlagsFromViewChain(
    NSView *_Nullable view, SharpenerChromeFlags *_Nullable flags);

/// Layer delegate walk (superlayers) plus the starting view’s superview chain.
void SharpenerMergeChromeFlagsFromCALayer(
    CALayer *_Nullable layer, SharpenerChromeFlags *_Nullable flags);

/// Best-effort owning NSWindow for a layer (delegate chain).
NSWindow *_Nullable SharpenerWindowForCALayer(CALayer *_Nullable layer);

/// YES if `view` or any superview looks like toolbar / unified titlebar chrome.
BOOL SharpenerViewChainHasTitlebarOrToolbar(NSView *_Nullable view);

/// “Liquid glass” containers that belong to the sidebar column (when not under
/// a titlebar chain).
BOOL SharpenerClassNameIsSidebarContainer(NSString *_Nullable className);

NS_ASSUME_NONNULL_END

#endif /* WINDOW_CHROME_ROLES_H */
