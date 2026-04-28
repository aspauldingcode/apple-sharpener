#pragma once
#import <Foundation/Foundation.h>

/** Mirror tweak suite plist keys into CF (AppleSharpener_*) so Dock/dylibs read them. */
void SharpenerMirrorSuiteDefaultsToCF(NSUserDefaults *suite);

/** Same distributed notification the GUI posts after saving. */
void SharpenerPostModulesUpdateNotification(void);
