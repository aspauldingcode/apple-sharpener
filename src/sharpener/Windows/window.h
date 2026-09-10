/**
 * Apple Sharpener: Window Sharpening API
 *
 * Defines the public interface for the Window sharpening module, including
 * initialization and toggle functions.
 */

#ifndef WINDOW_H
#define WINDOW_H

#import <Foundation/Foundation.h>

/**
 * Window sharpening API for apple-sharpener
 * Provides functions to control window corner radius modification
 */

/**
 * Initialize window sharpening — installs swizzles and notification observers.
 * Must be called AFTER AppKit is loaded (NSApplication and NSWindow classes
 * must exist). Typically called from the AppKit detection callback in
 * sharpener.m. Safe to call multiple times — only initializes once.
 */
void initWindowSharpener(void);

/**
 * Toggle square or squircle corners for application windows
 * @param enable Whether to enable custom corner radius
 * @param radius The corner radius to apply (0 for square corners)
 * @param squircle Whether to use continuous curves (squircles)
 * @param exponent The exponent applied to the superellipse shape (n)
 */
void toggleSquareCorners(BOOL enable, NSInteger radius, BOOL squircle,
                         CGFloat exponent);

#endif /* WINDOW_H */