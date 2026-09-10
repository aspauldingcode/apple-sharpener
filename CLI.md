# Apple Sharpener CLI

This document explains how to use the `sharpener` command‑line tool to control Apple Sharpener at runtime.

## Quick Start

```bash
# Global enable/disable (affects both windows and dock)
sharpener on
sharpener off
sharpener toggle

# Windows-specific controls
sharpener -w on
sharpener -w off
sharpener -w toggle
sharpener -w 40          # Set windows radius to 40

# Dock-specific controls
sharpener -d on
sharpener -d off
sharpener -d toggle
sharpener -d 0          # Set dock radius to 0

# Global radius (affects both if not explicitly set)
sharpener -r 10
sharpener --radius=10

# Show current settings
sharpener -s
sharpener --status

# Show version
sharpener -v
sharpener --version
```

## Commands

### Global Commands
- `on` — Enable sharpening for both windows and dock
- `off` — Disable sharpening for windows, dock, and squircle (continuous corners)
- `toggle` — Toggle sharpening on/off for windows and dock; when turning **off**, squircle is also disabled (`sharpener -q on` to re-enable corners)

### Windows-Specific Commands
- `-w on` — Enable window sharpening only
- `-w off` — Disable window sharpening only
- `-w toggle` — Toggle window sharpening on/off
- `-w <value>` — Set windows-specific radius (integer `>= 0`)

### Dock-Specific Commands
- `-d on` — Enable dock sharpening only
- `-d off` — Disable dock sharpening only
- `-d toggle` — Toggle dock sharpening on/off
- `-d <value>` — Set dock-specific radius (integer `>= 0`)

## Options

- `-r, --radius <value>` — Set global radius (affects both windows and dock if not explicitly set)
- `--radius=<value>` — Alternative syntax to set global radius
- `-w, --windows <value>` — Set windows-specific radius OR use with `on`/`off`/`toggle` to control windows
- `-d, --dock <value>` — Set dock-specific radius OR use with `on`/`off`/`toggle` to control dock
- `-s, --status` — Show current windows radius, dock radius, and status for each
- `-v, --version` — Show CLI version
- `-h, --help` — Show built‑in help

## Examples

```bash
# Set windows radius to 0 for sharp (square) corners
sharpener -w 0

# Set dock radius to 15
sharpener -d 15

# Set global radius (affects both if not explicitly set)
sharpener -r 40

# Enable windows only
sharpener -w on

# Disable dock only (windows remain enabled)
sharpener -d off

# Toggle windows on/off
sharpener -w toggle

# Set windows radius and enable immediately
sharpener -w on && sharpener -w 40

# Query current status
sharpener -s
# Output example:
# Global radius: 40
# Windows radius: 40 (using global)
# Dock radius: 15 (explicit)
# Windows status: on
# Dock status: on
# Global status: on

# Show version
sharpener --version
# Output example:
# Apple Sharpener version: 0.0.3
```

## Behavior Notes

### Radius Priority
- **Windows-specific radius** (`-w <value>`) takes precedence over global radius (`-r <value>`) for windows
- **Dock-specific radius** (`-d <value>`) takes precedence over global radius (`-r <value>`) for dock
- If a specific radius is not set, the component falls back to the global radius
- Global radius (`-r <value>`) applies to both windows and dock if neither has an explicit setting

### Enable/Disable Priority
- **Windows-specific toggle** (`-w on/off/toggle`) controls windows independently of dock
- **Dock-specific toggle** (`-d on/off/toggle`) controls dock independently of windows
- **Global toggle** (`on/off/toggle`) affects both windows and dock; **`off`** and the disable half of **`toggle`** also turn **squircle** off. Global **`on`** does not change squircle (use `-q on` to enable corners again).
- If windows/dock is explicitly disabled, it remains disabled even if global is enabled

### Window Targeting
- Targets standard application windows only; menus, popovers, HUD/utility windows are preserved.
- Fullscreen windows use a radius of `0` to avoid visual artifacts.
- Changes apply live across open windows; no app relaunch required.
- Enabled state and radius persist across apps via system notifications.

## Installation Path

- The installer places the CLI at `/usr/local/bin/sharpener`.
- If building from source via `make install`, the CLI is installed to the same path.

## Troubleshooting

- Run `sharpener -s` to confirm status and radius for both windows and dock.
- Ensure system requirements from the main README are met.
- If windows/dock don't respond to radius changes, check if they're explicitly disabled with `sharpener -w off` or `sharpener -d off`.