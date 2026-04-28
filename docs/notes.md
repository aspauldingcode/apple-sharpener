⚠️ The Real Leak Sources in Injection Tweaks
These are what actually leak in injected dylibs:
1. Swizzled Methods Holding Strong References
Example problem:
objc_setAssociatedObject(self, key, someObject, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
If someObject retains self → permanent leak.
2. Global Singletons That Never Release
Injected code often creates:
static MyManager *shared;
That lives forever in Finder.
That’s not technically a leak — but it never dies.

3. NotificationCenter Observers
If you do:
[[NSNotificationCenter defaultCenter] addObserver:self ...]
And never remove — leak.
4. NSTimer / CADisplayLink
If retained strongly and not invalidated → permanent cycle.
🔥 The Honest Answer
Switching languages won’t magically solve leaks.
You avoid leaks by:

Using ARC
Using weak references properly
Avoiding retain cycles in blocks
Cleaning up observers
Avoiding strong associated object cycles
🧩 If You Want Maximum Safety for macOS Injection
This is what I recommend:
Use Swift + ARC
But:
Keep injection bootstrap minimal in Obj-C
Do UI logic in Swift
Use [weak self] religiously
Avoid global state
This gives you:
Cocoa compatibility
Memory safety
Cleaner code
No heavy runtime like Go
💡 Bonus: Debugging Leaks in Injected Apps
Use:
Instruments → Leaks
Instruments → Allocations
MallocStackLogging
leaks Finder
You can attach Instruments directly to injected Finder/Dock.
🧠 Final Reality Check
If you're injecting into something like:
Finder
Dock
System Settings
LoginWindow
Memory leaks are usually from:
Cocoa patterns
Not from language choice
If you want, tell me:
What kind of tweak are you building?
Are you adding views? Overlays? Swizzling methods?
Which process are you injecting into?
I can tell you exactly where leaks will likely happen before you even write it.
