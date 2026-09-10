/**
 * Apple Sharpener: Window Chrome Roles Implementation
 *
 * Implements the heuristics to identify UI components based on class names
 * and view hierarchies.
 */

#import "window_chrome_roles.h"
#import <AppKit/AppKit.h>

void SharpenerChromeFlagsReset(SharpenerChromeFlags *flags) {
  if (!flags)
    return;
  flags->trafficLight = NO;
  flags->toolbarTitlebar = NO;
  flags->sidebar = NO;
}

static BOOL sharpener_class_matches_traffic(NSString *c) {
  if (!c.length)
    return NO;
  return [c containsString:@"ThemeCloseWidget"] ||
         [c containsString:@"ThemeZoomWidget"] ||
         [c containsString:@"ThemeMiniaturize"] ||
         [c containsString:@"ThemeWidget"] ||
         [c containsString:@"ThemeWidgetCell"] ||
         [c containsString:@"TrafficLight"] ||
         [c containsString:@"WindowButton"] ||
         [c containsString:@"StandardWindowButton"] ||
         [c containsString:@"NSWindowButton"];
}

static BOOL sharpener_class_matches_toolbar_titlebar(NSString *c) {
  if (!c.length)
    return NO;
  return [c containsString:@"Toolbar"] || [c containsString:@"NSToolbar"] ||
         [c containsString:@"Titlebar"] || [c containsString:@"TitleBar"] ||
         [c containsString:@"NSTitled"];
}

static BOOL sharpener_class_matches_sidebar_named(NSString *c) {
  if (!c.length)
    return NO;
  return [c containsString:@"NSSidebarView"] ||
         [c containsString:@"Sidebar"] || [c containsString:@"SideBar"] ||
         [c containsString:@"SourceList"] ||
         [c containsString:@"FullHeightSideBar"] ||
         [c containsString:@"InspectorSplit"] ||
         [c containsString:@"AuxiliarySidebar"] ||
         [c containsString:@"TSidebar"];
}

BOOL SharpenerClassNameIsSidebarContainer(NSString *className) {
  if (!className.length)
    return NO;
  if ([className containsString:@"NSScrollPocket"])
    return YES;
  if ([className containsString:@"NSBlurryAlleywayView"])
    return YES;
  if ([className containsString:@"NSContainerConcentricGlassEffectView"])
    return YES;
  if ([className containsString:@"12BackdropView"])
    return YES;
  return NO;
}

static BOOL sharpener_view_is_sidebar_material(NSView *view) {
  if (!view || ![view isKindOfClass:[NSVisualEffectView class]])
    return NO;
  return [(NSVisualEffectView *)view material] ==
         NSVisualEffectMaterialSidebar;
}

BOOL SharpenerViewChainHasTitlebarOrToolbar(NSView *view) {
  if (!view)
    return NO;
  for (NSView *v = view; v != nil; v = v.superview) {
    if (sharpener_class_matches_toolbar_titlebar(
            NSStringFromClass(v.class)))
      return YES;
  }
  return NO;
}

void SharpenerMergeChromeFlagsFromViewChain(NSView *view,
                                            SharpenerChromeFlags *flags) {
  if (!view || !flags)
    return;

  BOOL titlebarChain = SharpenerViewChainHasTitlebarOrToolbar(view);

  for (NSView *v = view; v != nil; v = v.superview) {
    NSString *c = NSStringFromClass(v.class);
    if (sharpener_class_matches_traffic(c))
      flags->trafficLight = YES;
    if (sharpener_class_matches_toolbar_titlebar(c))
      flags->toolbarTitlebar = YES;

    if (sharpener_class_matches_sidebar_named(c) ||
        sharpener_view_is_sidebar_material(v)) {
      flags->sidebar = YES;
    } else if (!titlebarChain && SharpenerClassNameIsSidebarContainer(c)) {
      flags->sidebar = YES;
    }
  }
}

void SharpenerMergeChromeFlagsFromCALayer(CALayer *layer,
                                          SharpenerChromeFlags *flags) {
  if (!layer || !flags)
    return;

  NSView *directView = nil;
  id delegate = layer.delegate;
  if (delegate && [delegate isKindOfClass:[NSView class]])
    directView = (NSView *)delegate;

  CALayer *current = layer;
  while (current) {
    id del = current.delegate;
    if (del && [del isKindOfClass:[NSView class]]) {
      NSView *cv = (NSView *)del;
      NSString *c = NSStringFromClass(cv.class);
      if (sharpener_class_matches_traffic(c))
        flags->trafficLight = YES;
      if (sharpener_class_matches_toolbar_titlebar(c))
        flags->toolbarTitlebar = YES;
      if (sharpener_class_matches_sidebar_named(c) ||
          sharpener_view_is_sidebar_material(cv))
        flags->sidebar = YES;
      else if (!SharpenerViewChainHasTitlebarOrToolbar(cv) &&
               SharpenerClassNameIsSidebarContainer(c))
        flags->sidebar = YES;
    }
    current = current.superlayer;
  }

  if (directView)
    SharpenerMergeChromeFlagsFromViewChain(directView, flags);
}

NSWindow *SharpenerWindowForCALayer(CALayer *layer) {
  if (!layer)
    return nil;
  id delegate = layer.delegate;
  if ([delegate isKindOfClass:[NSView class]]) {
    NSWindow *w = [(NSView *)delegate window];
    if (w)
      return w;
  }
  for (CALayer *cur = layer.superlayer; cur != nil; cur = cur.superlayer) {
    id del = cur.delegate;
    if ([del isKindOfClass:[NSView class]]) {
      NSWindow *w = [(NSView *)del window];
      if (w)
        return w;
    }
  }
  return nil;
}
