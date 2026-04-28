#pragma once

#import <Foundation/Foundation.h>

/**
 * File-only logging: ~/Library/Logs/AppleSharpener/sharpener.log
 * Never writes to stdout, stderr, or unified logging.
 *
 * Enable by building with -DAPPLE_SHARPENER_LOGS (see Makefile).
 */

#ifdef APPLE_SHARPENER_LOGS
void SharpenerLogAppend(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
#define SHARPENER_LOG(fmt, ...) SharpenerLogAppend(fmt, ##__VA_ARGS__)
#else
#define SharpenerLogAppend(...) ((void)0)
#define SHARPENER_LOG(fmt, ...) ((void)0)
#endif
