# Apple Sharpener

A macOS tweak that programmatically removes window corner radius to achieve clean, square corners on all application windows. This tweak is designed to work with the [Ammonia](https://github.com/CoreBedtime/ammonia) injection system.

![License](https://img.shields.io/badge/license-MIT-blue.svg)

![Preview 3](./previewMerged.png)

View more screenshots: [GALLERY.md](./GALLERY.md)

# Video:
[x.com/aspauldingcode/apple-sharpener](https://x.com/aspauldingcode/status/1889836621870318072)

## Features

- Square corners for application windows with configurable radius (`0` for sharp corners)
- Live control via CLI: `on`, `off`, `toggle` (no app restart needed)
- Live radius adjustment via `-r/--radius` with immediate effect across open windows
- Status query via `-s/--show-radius` (shows current radius and on/off state)
- Persists enabled state and radius across apps via `notifyd` channels
- Preserves system UI (menus, popovers, HUD/utility windows) by targeting standard app windows only
- Fullscreen-safe behavior; uses `0` radius in fullscreen to avoid visual artifacts
- Early injection through Ammonia ensures consistent appearance at app startup
- Universal build for Intel and Apple Silicon (x86_64, arm64, arm64e)
- System process blacklist to avoid injecting into critical daemons

## Requirements

- macOS Ventura or later (tested on Sonoma and Sequoia), though it probably works on 10.15 +
- [Ammonia](https://github.com/CoreBedtime/ammonia) injection system installed

### System Security Settings

For Ammonia injection to work, System Integrity Protection (SIP) must be disabled.

To disable SIP, you'll need to:

1. Boot into Recovery Mode:
   - For Apple Silicon Macs: Hold the power button until "Loading startup options" appears, then click "Options" and select a user/enter password
   - For Intel Macs: Hold Command-R during startup
2. Open Terminal (from Utilities menu) and run:
   ```bash
   csrutil disable
   ```
3. Restart your Mac:
4. For Apple Silicon Macs, enable the preview ABI by running:
   ```bash
   sudo nvram boot-args="-arm64e_preview_abi"
   ```

## Installation

### Pre-built Release
1. You can find the latest pre-built release Ammonia package from [Ammonia Injector releases page](https://github.com/CoreBedtime/ammonia/releases).
2. Download and install the latest Apple Sharpener release from the [Apple Sharpener releases page](../../releases).

### Building from Source

1. First, ensure you have the Ammonia injector installed:
   ```bash
   git clone https://github.com/CoreBedtime/ammonia
   cd ammonia
   ./install.sh
   ```

2. Then build and install Apple Sharpener:
   ```bash
   git clone https://github.com/aspauldingcode/apple-sharpener
   cd apple-sharpener
   make
   sudo make install
   ```

## Usage

See the CLI usage guide: [CLI.md](./CLI.md)

## Troubleshooting
Did you disable SIP?
Did you follow this [readme](./README.md#requirements) carefully?

## How It Works

Apple Sharpener uses method swizzling to modify the window corner mask and titlebar decoration view behavior of macOS applications. It specifically targets application windows while preserving the native appearance of menus, popovers, and other system UI elements.

## Contributing

Contributions are welcome! Feel free to:

- Open issues for bugs or feature requests
- Submit pull requests for improvements
- Share your ideas and suggestions

## License

Licensed under the [MIT License](./LICENSE).

## Acknowledgments

- [Ammonia](https://github.com/CoreBedtime/ammonia) for the injection framework
- [ZKSwizzle](https://github.com/alexzielenski/ZKSwizzle) for the swizzling implementation

## Support

If you encounter any issues or have questions:

1. Check the [Issues](../../issues) page for existing reports
2. Open a new issue if needed
3. Include your macOS version and device type when reporting problems

If you find Apple Sharpener useful, please consider frequent donations to support ongoing development:

- Ko‑fi: https://ko-fi.com/aspauldingcode

- Share Apple Sharpener with friends!

## ⚠️ Security Notice

This tweak requires disabling several macOS security features. Only proceed if you understand the implications of running your system with reduced security. Always download tweaks from trusted sources.
