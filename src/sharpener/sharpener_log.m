/**
 * Apple Sharpener: File Logging Implementation
 *
 * Provides a thread-safe, non-blocking logging mechanism that writes
 * directly to a persistent log file. Avoids using system logs (NSLog/os_log)
 * to prevent cluttering the user's console during global injection.
 */

#import "sharpener_log.h"
#import <stdarg.h>

#ifdef APPLE_SHARPENER_LOGS

static NSString *SharpenerLogFilePath(void) {
  static NSString *path;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSString *home = NSHomeDirectory();
    NSString *dir =
        [home stringByAppendingPathComponent:@"Library/Logs/AppleSharpener"];
    // Ensure the log directory exists
    [[NSFileManager defaultManager]
        createDirectoryAtPath:dir
        withIntermediateDirectories:YES
                         attributes:nil
                          error:nil];
    path = [dir stringByAppendingPathComponent:@"sharpener.log"];
  });
  return path;
}

static dispatch_queue_t SharpenerLogQueue(void) {
  static dispatch_queue_t q;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    // Serial queue to ensure log entries are written in order and without contention
    q = dispatch_queue_create("com.aspauldingcode.apple_sharpener.filelog",
                              DISPATCH_QUEUE_SERIAL);
  });
  return q;
}

void SharpenerLogAppend(NSString *format, ...) {
  if (!format)
    return;

  va_list args;
  va_start(args, format);
  NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  // Snapshot on caller thread — queue only does I/O
  NSString *path = SharpenerLogFilePath();
  NSString *proc =
      [[NSProcessInfo processInfo] processName] ?: @"?";
  int pid = (int)[[NSProcessInfo processInfo] processIdentifier];

  dispatch_async(SharpenerLogQueue(), ^{
    if (!path.length)
      return;

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *line = [NSString
        stringWithFormat:@"[%@] [%@:%d] %@\n",
                         [fmt stringFromDate:[NSDate date]], proc, pid, body];
    NSData *chunk = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!chunk.length)
      return;

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
      [chunk writeToFile:path atomically:YES];
      return;
    }

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
      NSMutableData *all =
          [NSMutableData dataWithContentsOfFile:path] ?: [NSMutableData data];
      [all appendData:chunk];
      [all writeToFile:path atomically:YES];
      return;
    }
    @try {
      [fh seekToEndOfFile];
      [fh writeData:chunk];
      [fh synchronizeFile];
      [fh closeFile];
    } @catch (__unused NSException *e) {
      @try {
        [fh closeFile];
      } @catch (__unused NSException *e2) {
      }
    }
  });
}

#endif /* APPLE_SHARPENER_LOGS */
