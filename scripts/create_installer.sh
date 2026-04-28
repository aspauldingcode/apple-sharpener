#!/bin/bash

# Get the repository root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Version - read from VERSION file
VERSION=$(cat "$REPO_ROOT/VERSION")
PKG_NAME="apple-sharpener-${VERSION}.pkg"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"
BUILD_FILE="$REPO_ROOT/out/libapple_sharpener.dylib"
CLI_BUILD_FILE="$REPO_ROOT/out/sharpener"

# Change to repository root
cd "$REPO_ROOT"

# Check if version already exists in CHANGELOG
if [ -f "$CHANGELOG_FILE" ] && grep -q "## \[${VERSION}\]" "$CHANGELOG_FILE"; then
    echo "Warning: Version ${VERSION} already exists in CHANGELOG"
    echo "Consider updating the VERSION file to a new version number"
    echo "Continuing with installer creation..."
fi

# Check if build exists, if not, run make
if [ ! -f "$BUILD_FILE" ] || [ ! -f "$CLI_BUILD_FILE" ]; then
    echo "Build not found. Running make..."
    if ! make; then
        echo "Error: Build failed"
        exit 1
    fi
fi

# Create temporary directory structure
TEMP_DIR="$(mktemp -d)"
PAYLOAD_DIR="$TEMP_DIR/payload"
SCRIPTS_DIR="$TEMP_DIR/scripts"

mkdir -p "$PAYLOAD_DIR/var/ammonia/core/tweaks"
mkdir -p "$SCRIPTS_DIR"

# Copy files to payload
if ! cp "$BUILD_FILE" "$PAYLOAD_DIR/var/ammonia/core/tweaks/"; then
    echo "Error: Failed to copy dylib"
    rm -rf "$TEMP_DIR"
    exit 1
fi

if ! cp libapple_sharpener.dylib.blacklist "$PAYLOAD_DIR/var/ammonia/core/tweaks/"; then
    echo "Error: Failed to copy blacklist"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Copy CLI and Helper to /usr/local/bin
mkdir -p "$PAYLOAD_DIR/usr/local/bin"
if ! cp "$CLI_BUILD_FILE" "$PAYLOAD_DIR/usr/local/bin/"; then
    echo "Error: Failed to copy CLI"
    rm -rf "$TEMP_DIR"
    exit 1
fi
if ! cp "$REPO_ROOT/out/sharpener-helper" "$PAYLOAD_DIR/usr/local/bin/"; then
    echo "Error: Failed to copy Helper"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Copy ASConfigurator app to /Applications
mkdir -p "$PAYLOAD_DIR/Applications"
if ! cp -r "$REPO_ROOT/src/gui/ASConfigurator/Apple Sharpener Configurator.app" "$PAYLOAD_DIR/Applications/"; then
    echo "Error: Failed to copy Apple Sharpener Configurator"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Copy LaunchAgents
mkdir -p "$PAYLOAD_DIR/Library/LaunchAgents"
if ! cp "$REPO_ROOT/src/helper/com.aspauldingcode.sharpener.helper.plist" "$PAYLOAD_DIR/Library/LaunchAgents/"; then
    echo "Error: Failed to copy helper plist"
    rm -rf "$TEMP_DIR"
    exit 1
fi
if ! cp "$REPO_ROOT/src/gui/ASConfigurator/com.aspauldingcode.asconfigurator.plist" "$PAYLOAD_DIR/Library/LaunchAgents/"; then
    echo "Error: Failed to copy configurator plist"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Create postinstall script
cat > "$SCRIPTS_DIR/postinstall" << 'EOF'
#!/bin/bash

# Remove any root-loaded instances
launchctl bootout system /Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist 2>/dev/null || launchctl unload /Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist 2>/dev/null || launchctl unload /Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist 2>/dev/null || true

# Load for the current console user
USER_NAME=$(stat -f %Su /dev/console)
if [ -n "$USER_NAME" ] && [ "$USER_NAME" != "root" ]; then
    USER_ID=$(id -u "$USER_NAME")
    launchctl bootstrap gui/$USER_ID /Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist 2>/dev/null || sudo -u "$USER_NAME" launchctl load /Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist 2>/dev/null || true
    launchctl bootstrap gui/$USER_ID /Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist 2>/dev/null || sudo -u "$USER_NAME" launchctl load /Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist 2>/dev/null || true
fi

# Restart Ammonia service (script runs as root in pkg context; sudo not required)
sleep 2
launchctl bootout system /Library/LaunchDaemons/com.bedtime.ammonia.plist 2>/dev/null || true
sleep 2
launchctl bootstrap system /Library/LaunchDaemons/com.bedtime.ammonia.plist

exit 0
EOF

chmod +x "$SCRIPTS_DIR/postinstall"

# Build package
pkgbuild --root "$PAYLOAD_DIR" \
         --scripts "$SCRIPTS_DIR" \
         --identifier com.aspauldingcode.apple-sharpener \
         --version "$VERSION" \
         --install-location "/" \
         "$PKG_NAME"

# Check if package was created successfully
if [ $? -eq 0 ] && [ -f "$PKG_NAME" ]; then
    # Clean up temp directory
    rm -rf "$TEMP_DIR"

    echo "Created installer package: $REPO_ROOT/$PKG_NAME"
    echo "Version $VERSION packaged successfully"
    echo "Note: Update CHANGELOG.md manually to document this release"
else
    # Clean up on failure
    rm -rf "$TEMP_DIR"
    [ -f "$PKG_NAME" ] && rm "$PKG_NAME"
    echo "Error: Failed to create installer package"
    exit 1
fi