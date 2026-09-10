/**
 * Apple Sharpener: Preference Mirroring
 *
 * Provides utilities to mirror standard NSUserDefaults into the global
 * CoreFoundation preferences domain. This allows sandboxed and background
 * processes to read settings that they otherwise couldn't access via
 * standard suite name APIs.
 */

#pragma once
#import <Foundation/Foundation.h>

/** Mirror tweak suite plist keys into CF (AppleSharpener_*) so Dock/dylibs read them. */
void SharpenerMirrorSuiteDefaultsToCF(NSUserDefaults *suite);

/** Same distributed notification the GUI posts after saving. */
void SharpenerPostModulesUpdateNotification(void);
