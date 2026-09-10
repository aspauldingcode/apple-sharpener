# Apple Sharpener Documentation

Apple Sharpener brings continuous squircle corners, fully custom border strokes, and sharp docking to macOS. It achieves this by injecting into AppKit applications and modifying their `NSWindow` frames and CoreAnimation layers.

## Installation

### From Source (Makefile)
To install from source, ensure you have the macOS SDK and Command Line Tools installed.
```bash
git clone https://github.com/aspauldingcode/apple-sharpener.git
cd apple-sharpener
make install
```
This will:
1. Compile `libapple_sharpener.dylib`, `sharpener` CLI, and `sharpener-helper` daemon.
2. Install the dylib to `/var/ammonia/core/tweaks/`.
3. Install the tools to `/usr/local/bin/`.
4. Load the `com.aspauldingcode.sharpener.helper.plist` launch agent.

### Uninstallation
```bash
make uninstall
```
This cleanly unloads the Launch Agent, removes the binaries, and clears the tweak.

## Configuration Guide

Apple Sharpener can be configured both imperatively via the command line, and declaratively using a KDL configuration file and macOS GUI.

### Graphical Configuration

Apple Sharpener installs **`sharpener-configurator`** to `/usr/local/bin` and starts it via `com.aspauldingcode.asconfigurator` LaunchAgent. It is a **menubar-only** agent (activation policy accessory): it does not live in `/Applications` and does not get a Dock tile. The **Liquid Glass** settings UI is built in AppKit/SwiftUI; edits apply to your `.kdl` and live prefs immediately.

### KDL Declarative Configuration

You can customize the underlying configuration file at `~/.config/sharpener/config.kdl`. The file is monitored by the `sharpener-helper` launch agent, and any changes saved to this file will take effect globally across all windows instantaneously.

**Example `config.kdl` Schema:**
```kdl
sharpener {
    global {
        radius 14
        squircle true
        squircle_exponent 4.0
        shadows true
    }
    windows {
        enabled true
        borders true
        border_width 2.0
        border_color_active "0xFF0000FF"
        border_color_inactive "0x0000FFFF"
    }
    dock {
        enabled true
    }
    rules {
        app "com.apple.Safari" {
            radius 0
            squircle false
            shadows false
            borders false
        }
    }
}
```

### CLI Usage

The `sharpener` CLI allows you to view status and dynamically toggle Apple Sharpener components.

```bash
# General
sharpener status         # Returns the current state (enabled/disabled, radius)
sharpener toggle         # Toggles global Apple Sharpener on and off

# Window Corners
sharpener -w on          # Enable Apple Sharpener for Windows
sharpener -w off         # Disable Apple Sharpener for Windows
sharpener -w 12          # Sets Window corner radius to 12

# Dock
sharpener -d on          # Enable Apple Sharpener for the Dock
sharpener -d off         # Disable Apple Sharpener for the Dock
sharpener -d 16          # Sets Dock corner radius to 16

# Squircle Continuous Corners
sharpener -s on          # Enable squircle formulas for rounded corners
sharpener -s off         # Disable squircle corners (fast standard rendering)
sharpener -e 3.5         # Set Squircle Exponent (higher = more continuous, default is 4.0)

# Other
sharpener --json         # Get status formatted in JSON for scripts
```

## Issue Reporting

If you encounter crashes or graphics anomalies:
1. Ensure the failing app is not already explicitly added to the `/var/ammonia/core/tweaks/libapple_sharpener.dylib.blacklist`.
2. Provide the Console.app log for the crash (e.g., look for Thread 0 crashing inside `ZKSwizzle` or `apple_sharpener` dylibs).
3. If an app fails to visually transform, supply a layer dump. You can generate one via:
```bash
make dumpwindow APP="Brave Browser"
```
Submit the generated `Brave_Browser_window_dump.txt` along with your bug report.
