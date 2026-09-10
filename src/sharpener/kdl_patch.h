/**
 * Apple Sharpener: KDL File Patcher
 *
 * Provides lightweight helpers that update specific values inside the
 * sharpener config.kdl file without re-parsing or regenerating the whole
 * document.  Used by the CLI so that every `sharpener` command keeps
 * config.kdl in sync, making the daemon file-watcher and the GUI
 * file-watcher the authoritative source of truth.
 *
 * Design: simple line-by-line text substitution.  The generated KDL has
 * one key per line, so this is safe and fast.
 */

#pragma once
#import <Foundation/Foundation.h>

/**
 * Read the whole config.kdl into a mutable string.
 * Returns nil if the file cannot be read.
 */
static inline NSMutableString *kdl_read(void) {
  NSString *home = NSHomeDirectory();
  NSString *path =
      [home stringByAppendingPathComponent:@".config/sharpener/config.kdl"];
  NSError *err = nil;
  NSString *s =
      [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
  if (!s) return nil;
  return [NSMutableString stringWithString:s];
}

/**
 * Atomically write `content` back to config.kdl (backs up existing file first).
 */
static inline BOOL kdl_write(NSString *content) {
  NSString *home = NSHomeDirectory();
  NSString *path =
      [home stringByAppendingPathComponent:@".config/sharpener/config.kdl"];
  NSString *dir = [path stringByDeletingLastPathComponent];
  [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
  NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
  if (!data) return NO;
  return [data writeToFile:path atomically:YES];
}

/**
 * Replace the **first** occurrence of `key <any value>` (within optional
 * surrounding whitespace) inside `blockName { … }`.  If the key is not
 * found a new line is inserted before the closing brace of that block.
 *
 * `value` should already be formatted as a KDL literal, e.g. "true", "14",
 * or "\"default\"".
 *
 * Returns YES on success.
 */
static inline BOOL kdl_patch_key(NSMutableString *kdl,
                                  NSString *blockName,
                                  NSString *key,
                                  NSString *value) {
  if (!kdl || !blockName || !key || !value) return NO;

  // Build a regex that matches `key <anything>` lines inside the block.
  // We look for the block header then walk line-by-line.
  NSArray<NSString *> *lines = [kdl componentsSeparatedByString:@"\n"];
  NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:lines.count];

  BOOL inBlock = NO;
  NSInteger depth = 0;
  BOOL patched = NO;

  for (NSString *rawLine in lines) {
    NSString *trimmed = [rawLine stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceCharacterSet]];

    if (!inBlock) {
      // Detect block header: blockName (possibly followed by more tokens) + {
      if ([trimmed hasPrefix:blockName] && [trimmed containsString:@"{"]) {
        inBlock = YES;
        depth = 1;
      }
      [out addObject:rawLine];
      continue;
    }

    // Track brace depth
    for (NSUInteger i = 0; i < trimmed.length; i++) {
      unichar c = [trimmed characterAtIndex:i];
      if (c == '{') depth++;
      else if (c == '}') depth--;
    }

    // We are one level deep (direct children of blockName)
    if (depth == 1 && !patched) {
      // Does this line define `key`?
      NSString *prefix = [NSString stringWithFormat:@"%@ ", key];
      if ([trimmed hasPrefix:prefix] || [trimmed isEqualToString:key]) {
        // Preserve leading whitespace
        NSUInteger wsLen = 0;
        while (wsLen < rawLine.length) {
          unichar c = [rawLine characterAtIndex:wsLen];
          if (c == ' ' || c == '\t') wsLen++; else break;
        }
        NSString *indent = [rawLine substringToIndex:wsLen];
        NSString *newLine = [NSString stringWithFormat:@"%@%@ %@", indent, key, value];
        [out addObject:newLine];
        patched = YES;
        continue;
      }
    }

    // Closing brace of our target block and key not yet found → insert before
    if (depth == 0 && inBlock && !patched) {
      // Determine the indent of this closing brace and use 4 more spaces
      NSUInteger wsLen = 0;
      while (wsLen < rawLine.length) {
        unichar c = [rawLine characterAtIndex:wsLen];
        if (c == ' ' || c == '\t') wsLen++; else break;
      }
      NSString *indent = [[rawLine substringToIndex:wsLen] stringByAppendingString:@"    "];
      NSString *newLine = [NSString stringWithFormat:@"%@%@ %@", indent, key, value];
      [out addObject:newLine];
      patched = YES;
      inBlock = NO;
    } else if (depth == 0) {
      inBlock = NO;
    }

    [out addObject:rawLine];
  }

  if (!patched) return NO;

  [kdl setString:[out componentsJoinedByString:@"\n"]];
  return YES;
}

/**
 * Convenience: read → patch one key → write.
 * Operates on the root `sharpener` block by default.
 */
static inline BOOL kdl_set_in_block(NSString *blockName, NSString *key, NSString *value) {
  NSMutableString *kdl = kdl_read();
  if (!kdl) return NO;
  if (!kdl_patch_key(kdl, blockName, key, value)) {
    // Block might not exist yet – fall back to root sharpener block
    if (![blockName isEqualToString:@"sharpener"]) {
      if (!kdl_patch_key(kdl, @"sharpener", key, value)) return NO;
    } else {
      return NO;
    }
  }
  return kdl_write(kdl);
}

/** Patch a boolean key inside a named block. */
static inline BOOL kdl_set_bool(NSString *block, NSString *key, BOOL value) {
  return kdl_set_in_block(block, key, value ? @"true" : @"false");
}

/** Patch an integer key inside a named block. */
static inline BOOL kdl_set_int(NSString *block, NSString *key, NSInteger value) {
  return kdl_set_in_block(block, key, [NSString stringWithFormat:@"%ld", (long)value]);
}

/** Patch a double key inside a named block. */
static inline BOOL kdl_set_double(NSString *block, NSString *key, double value) {
  return kdl_set_in_block(block, key, [NSString stringWithFormat:@"%.6g", value]);
}
