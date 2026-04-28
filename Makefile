ifeq (,$(filter help completion,$(MAKECMDGOALS)))
  # Dynamic compiler detection
  XCODE_PATH := $(shell xcode-select -p)
  XCODE_TOOLCHAIN := $(XCODE_PATH)/Toolchains/XcodeDefault.xctoolchain
  CC := $(shell xcrun -find clang)
  CXX := $(shell xcrun -find clang++)

  # SDK paths
  SDKROOT ?= $(shell xcrun --show-sdk-path)
  ISYSROOT := $(shell xcrun -sdk macosx --show-sdk-path)
  INCLUDE_PATH := $(shell xcrun -sdk macosx --show-sdk-platform-path)/Developer/SDKs/MacOSX.sdk/usr/include
else
  # Fallbacks for non-build goals to avoid SDK discovery
  CC := clang
  CXX := clang++
  SDKROOT :=
  ISYSROOT :=
  INCLUDE_PATH :=
endif

.DEFAULT_GOAL := all

# Compiler and flags
CFLAGS = -Wall -Wextra -O2 \
    -fobjc-arc \
    -isysroot $(SDKROOT) \
    -iframework $(SDKROOT)/System/Library/Frameworks \
    -F/System/Library/PrivateFrameworks \
    -IZKSwizzle \
    -I$(SOURCE_DIR)/sharpener
ARCHS = -arch x86_64 -arch arm64 -arch arm64e
FRAMEWORK_PATH = $(SDKROOT)/System/Library/Frameworks
PRIVATE_FRAMEWORK_PATH = $(SDKROOT)/System/Library/PrivateFrameworks
PUBLIC_FRAMEWORKS = -framework Foundation -framework AppKit -framework QuartzCore -framework Cocoa \
	-framework CoreFoundation -framework IOSurface

ESC := \033
RESET := $(ESC)[0m
BOLD := $(ESC)[1m
ITALIC := $(ESC)[3m
RED := $(ESC)[31m
GREEN := $(ESC)[32m
YELLOW := $(ESC)[33m
BLUE := $(ESC)[34m
MAGENTA := $(ESC)[35m
CYAN := $(ESC)[36m

# Project name and paths
PROJECT = apple_sharpener
DYLIB_NAME = lib$(PROJECT).dylib
CLI_NAME = sharpener
BUILD_DIR = out
SOURCE_DIR = src
INSTALL_DIR = /var/ammonia/core/tweaks
CLI_INSTALL_DIR = /usr/local/bin

# Source files (main dylib - hook is separate)
DYLIB_SOURCES = $(SOURCE_DIR)/sharpener/sharpener.m \
                $(SOURCE_DIR)/sharpener/sharpener_log.m \
                $(SOURCE_DIR)/sharpener/Windows/window.m \
                $(SOURCE_DIR)/sharpener/Dock/dock.m \
                ZKSwizzle/ZKSwizzle.m
DYLIB_OBJECTS = $(patsubst %.m,$(BUILD_DIR)/%.o,$(filter %.m,$(DYLIB_SOURCES))) \
                $(patsubst %.mm,$(BUILD_DIR)/%.o,$(filter %.mm,$(DYLIB_SOURCES)))

# CLI tool source and object
CLI_SOURCE = $(SOURCE_DIR)/sharpener/clitool.m
CLI_OBJECT = $(BUILD_DIR)/sharpener/clitool.o

# Helper daemon source and object
HELPER_NAME = sharpener-helper
HELPER_SOURCE = $(SOURCE_DIR)/helper/sharpener_helper.m
HELPER_OBJECT = $(BUILD_DIR)/helper/sharpener_helper.o

# GUI Configurator App
GUI_DIR = $(SOURCE_DIR)/gui/ASConfigurator
GUI_APP_NAME = Apple Sharpener Configurator
GUI_APP = $(GUI_APP_NAME).app
GUI_BUILD_XCODE = $(GUI_DIR)/.build/release/AppleSharpenerConfigurator

# Dock dump tool
DUMP_SOURCE = $(SOURCE_DIR)/sharpener/Dock/dockdump.m
DUMP_DYLIB_NAME = libdockdump.dylib
DUMP_OBJECT = $(BUILD_DIR)/src/sharpener/Dock/dockdump.o
DUMP_INSTALL_PATH = $(INSTALL_DIR)/$(DUMP_DYLIB_NAME)
DUMP_WHITELIST_SOURCE = libdockdump.dylib.whitelist
DUMP_WHITELIST_DEST = $(INSTALL_DIR)/$(DUMP_WHITELIST_SOURCE)

# Window dump tool (generic, works with any app)
WINDOW_DUMP_SOURCE = $(SOURCE_DIR)/sharpener/Windows/windowdump.m
WINDOW_DUMP_DYLIB_NAME = libwindowdump.dylib
WINDOW_DUMP_OBJECT = $(BUILD_DIR)/src/sharpener/Windows/windowdump.o
WINDOW_DUMP_INSTALL_PATH = $(INSTALL_DIR)/$(WINDOW_DUMP_DYLIB_NAME)
WINDOW_DUMP_WHITELIST_NAME = libwindowdump.dylib.whitelist
WINDOW_DUMP_WHITELIST_DEST = $(INSTALL_DIR)/$(WINDOW_DUMP_WHITELIST_NAME)

# Installation targets
INSTALL_PATH = $(INSTALL_DIR)/$(DYLIB_NAME)
CLI_INSTALL_PATH = $(CLI_INSTALL_DIR)/$(CLI_NAME)
BLACKLIST_SOURCE = lib$(PROJECT).dylib.blacklist
BLACKLIST_DEST = $(INSTALL_DIR)/lib$(PROJECT).dylib.blacklist

# Dylib settings
DYLIB_FLAGS = -dynamiclib \
              -install_name @rpath/$(DYLIB_NAME) \
              -compatibility_version 1.0.0 \
              -current_version 1.0.0

# Logging to ~/Library/Logs/AppleSharpener/sharpener.log only (never stdout/stderr)
LOGS_FLAGS ?= -DAPPLE_SHARPENER_LOGS

# Create build directory and subdirectories
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(BUILD_DIR)/ZKSwizzle
	@mkdir -p $(BUILD_DIR)/src/sharpener
	@mkdir -p $(BUILD_DIR)/src/sharpener/Dock
	@mkdir -p $(BUILD_DIR)/src/sharpener/Windows

# Build target
all: $(BUILD_DIR)/$(DYLIB_NAME) $(BUILD_DIR)/$(CLI_NAME) $(BUILD_DIR)/$(HELPER_NAME) configurator ## Build dylib, CLI, helper, and GUI Configurator

build: all

# Compile Objective-C source files
# Filter out shadow hook messages that interfere with build
# Note: This is a workaround for MacEnhance shadow hooks injecting into compiler processes
$(BUILD_DIR)/%.o: %.m | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	@TMPFILE=$$(mktemp); \
	$(CC) $(CFLAGS) $(ARCHS) $(LOGS_FLAGS) -c $< -o $@ 2>$$TMPFILE; \
	EXIT_CODE=$$?; \
	grep -v "^\[!\] shadows:" $$TMPFILE | grep -v "^\[shadows\]" >&2; \
	rm -f $$TMPFILE; \
	exit $$EXIT_CODE



# Link main dylib
$(BUILD_DIR)/$(DYLIB_NAME): $(DYLIB_OBJECTS)
	$(CC) $(DYLIB_FLAGS) $(ARCHS) $(DYLIB_OBJECTS) -o $@ \
	-F$(FRAMEWORK_PATH) \
	-F$(PRIVATE_FRAMEWORK_PATH) \
	$(PUBLIC_FRAMEWORKS) \
	-undefined dynamic_lookup \
	-L$(SDKROOT)/usr/lib

# Build CLI tool (updated to avoid linking UI frameworks)
$(BUILD_DIR)/$(CLI_NAME): $(CLI_SOURCE) | $(BUILD_DIR)
	@rm -f $(BUILD_DIR)/$(CLI_NAME)
	@VERSION=$$(cat VERSION 2>/dev/null | head -1 | tr -d '\n\r'); \
	TMPFILE=$$(mktemp); \
	($(CC) $(CFLAGS) $(ARCHS) $(LOGS_FLAGS) $(CLI_SOURCE) \
		$(SOURCE_DIR)/sharpener/sharpener_cf_prefs.m \
		-DAPPLE_SHARPENER_VERSION="\"$$VERSION\"" \
		-framework Foundation \
		-framework CoreFoundation \
		-o $@ 2>$$TMPFILE; EXIT_CODE=$$?; \
	grep -v "^\[!\] shadows:" $$TMPFILE | grep -v "^\[shadows\]" >&2; \
	rm -f $$TMPFILE; exit $$EXIT_CODE)

# Build Helper daemon
$(BUILD_DIR)/$(HELPER_NAME): $(HELPER_SOURCE) | $(BUILD_DIR)
	@mkdir -p $(BUILD_DIR)/helper
	@rm -f $(BUILD_DIR)/$(HELPER_NAME)
	@TMPFILE=$$(mktemp); \
	($(CC) $(CFLAGS) $(ARCHS) $(LOGS_FLAGS) $(HELPER_SOURCE) \
		$(SOURCE_DIR)/sharpener/sharpener_log.m \
		-framework Foundation \
		-framework CoreFoundation \
		-o $@ 2>$$TMPFILE; EXIT_CODE=$$?; \
	grep -v "^\[!\] shadows:" $$TMPFILE | grep -v "^\[shadows\]" >&2; \
	rm -f $$TMPFILE; exit $$EXIT_CODE)

# Build GUI Configurator
configurator: ## Build ASConfigurator GUI Application
	@printf "$(BOLD)$(CYAN)Building$(RESET) ASConfigurator GUI App...\n"
	@cd $(GUI_DIR) && swift build -c release
	@mkdir -p "$(GUI_DIR)/$(GUI_APP)/Contents/MacOS"
	@cp -f "$(GUI_BUILD_XCODE)" "$(GUI_DIR)/$(GUI_APP)/Contents/MacOS/$(GUI_APP_NAME)"
	@printf "$(GREEN)Built$(RESET) $(BOLD)%s$(RESET)\n" "$(GUI_APP)"

# Install dylib, CLI tool, helper, and GUI app
install: all ## Build and install dylib, CLI, helper, and GUI to system
	@if [ -n "$$SUDO_USER" ]; then \
		chown -R $$SUDO_USER $(BUILD_DIR) 2>/dev/null || true; \
	fi
	@printf "$(BOLD)$(CYAN)Installing$(RESET) Apple Sharpener suite...\n"
	@printf "  $(YELLOW)→$(RESET) Creating target directories...\n"
	@sudo mkdir -p $(INSTALL_DIR)
	@sudo mkdir -p $(CLI_INSTALL_DIR)
	@printf "  $(YELLOW)→$(RESET) Installing Core Tweak and CLI utilities...\n"
	@sudo install -m 755 $(BUILD_DIR)/$(DYLIB_NAME) $(INSTALL_DIR)
	@sudo install -m 755 $(BUILD_DIR)/$(CLI_NAME) $(CLI_INSTALL_DIR)
	@sudo install -m 755 $(BUILD_DIR)/$(HELPER_NAME) $(CLI_INSTALL_DIR)
	@printf "  $(YELLOW)→$(RESET) Installing GUI Configurator to /Applications...\n"
	@sudo pkill -9 "$(GUI_APP_NAME)" 2>/dev/null || true
	@sudo pkill -9 "ASConfigurator" 2>/dev/null || true
	sudo rm -rf "/Applications/$(GUI_APP)"
	sudo cp -R "$(GUI_DIR)/$(GUI_APP)" "/Applications/"
	sudo chmod -R 755 "/Applications/$(GUI_APP)"
	@printf "  $(YELLOW)→$(RESET) Registering LaunchAgents to User Domain...\n"
	@CURRENT_USER=$${SUDO_USER:-$$USER}; \
	CURRENT_UID=$$(id -u "$$CURRENT_USER"); \
	USER_HOME=$$(eval echo "~$$CURRENT_USER"); \
	sudo -u "$$CURRENT_USER" mkdir -p "$$USER_HOME/Library/LaunchAgents"; \
	sudo cp src/helper/com.aspauldingcode.sharpener.helper.plist "$$USER_HOME/Library/LaunchAgents/"; \
	sudo chown "$$CURRENT_USER" "$$USER_HOME/Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist"; \
	sudo cp src/gui/ASConfigurator/com.aspauldingcode.asconfigurator.plist "$$USER_HOME/Library/LaunchAgents/"; \
	sudo chown "$$CURRENT_USER" "$$USER_HOME/Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist"; \
	sudo -u "$$CURRENT_USER" launchctl bootout gui/$$CURRENT_UID "$$USER_HOME/Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist" 2>/dev/null || true; \
	sudo -u "$$CURRENT_USER" launchctl bootout gui/$$CURRENT_UID "$$USER_HOME/Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist" 2>/dev/null || true; \
	sudo launchctl bootout system /Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist 2>/dev/null || true; \
	sudo launchctl bootout system /Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist 2>/dev/null || true; \
	sudo rm -f /Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist 2>/dev/null || true; \
	sudo rm -f /Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist 2>/dev/null || true; \
	sudo pkill -9 sharpener-helper 2>/dev/null || true; \
	sudo pkill -9 "$(GUI_APP_NAME)" 2>/dev/null || true; \
	sudo pkill -9 "ASConfigurator" 2>/dev/null || true; \
	printf "  $(YELLOW)→$(RESET) Bootstrapping Daemons into User Session $(BOLD)(Waiting on launchctl)$(RESET)...\n"; \
	sudo -u "$$CURRENT_USER" launchctl enable gui/$$CURRENT_UID/com.aspauldingcode.sharpener.helper 2>/dev/null || true; \
	sudo -u "$$CURRENT_USER" launchctl enable gui/$$CURRENT_UID/com.aspauldingcode.asconfigurator 2>/dev/null || true; \
	sudo -u "$$CURRENT_USER" launchctl bootstrap gui/$$CURRENT_UID "$$USER_HOME/Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist" 2>/dev/null || true; \
	sudo -u "$$CURRENT_USER" launchctl bootstrap gui/$$CURRENT_UID "$$USER_HOME/Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist" 2>/dev/null || true; \
	sudo -u "$$CURRENT_USER" launchctl kickstart -k gui/$$CURRENT_UID/com.aspauldingcode.sharpener.helper 2>/dev/null || true; \
	sudo -u "$$CURRENT_USER" launchctl kickstart -k gui/$$CURRENT_UID/com.aspauldingcode.asconfigurator 2>/dev/null || true
	@printf "  $(YELLOW)→$(RESET) Transitioning whitelists to blacklist...\n"
	@sudo rm -f $(INSTALL_DIR)/lib$(PROJECT).dylib.whitelist 2>/dev/null || true
	@if [ -f $(BLACKLIST_SOURCE) ]; then \
		sudo cp $(BLACKLIST_SOURCE) $(BLACKLIST_DEST); \
		sudo chmod 644 $(BLACKLIST_DEST); \
	fi
	@printf "$(GREEN)Installed$(RESET) $(BOLD)%s$(RESET), $(BOLD)%s$(RESET), $(BOLD)%s$(RESET), and $(BOLD)%s$(RESET)\n" "$(DYLIB_NAME)" "$(CLI_NAME)" "$(HELPER_NAME)" "$(GUI_APP)"
	@printf "$(YELLOW)Restarting Dock$(RESET) to load new dylib...\n"
	@pkill -9 "Dock" 2>/dev/null || true

# Test target that builds, installs, and relaunches test applications
test: install ## Clean, build, install, and restart test applications
	@printf "$(BOLD)$(CYAN)Force quitting$(RESET) test applications and Dock...\n"
	$(eval TEST_APPS := Spotify "System Settings" Chess soffice "Brave Browser" Beeper Safari Finder "qBittorrent" zoom.us "Logic Pro" Xcode Grapher Calculator "Activity Monitor" "TextEdit" Mail Calendar Notes Preview "QuickTime Player" "System Preferences")
	@for app in $(TEST_APPS); do \
		pkill -9 "$$app" 2>/dev/null || true; \
		done
	@printf "$(YELLOW)Killing Dock$(RESET) to reload with new dylib...\n"
	@pkill -9 "Dock" 2>/dev/null || true
	@printf "$(BOLD)$(CYAN)Relaunching$(RESET) test applications...\n"
	@for app in $(TEST_APPS); do \
		if [ "$$app" != "soffice" ] && [ "$$app" != "zoom.us" ]; then \
			open -a "$$app" 2>/dev/null || true; \
		elif [ "$$app" = "zoom.us" ]; then \
			open -a "zoom.us" 2>/dev/null || true; \
		fi; \
		done
	@printf "$(YELLOW)Waiting 30 seconds$(RESET) for applications to initialize...\n"
	@sleep 30
	@printf "$(BOLD)$(CYAN)Force quitting$(RESET) test applications...\n"
	@for app in $(TEST_APPS); do \
		pkill -9 "$$app" 2>/dev/null || true; \
		done
	@printf "$(GREEN)Done$(RESET): Test applications and Dock restarted, and applications quit after 30s\n"

# End test - force kill all test applications and uninstall
end-test: uninstall ## Force kill all test applications and uninstall
	@printf "$(BOLD)$(YELLOW)Force quitting$(RESET) all test applications...\n"
	$(eval TEST_APPS := Spotify "System Settings" Chess soffice "Brave Browser" Beeper Safari Finder "qBittorrent" zoom.us "Logic Pro" Xcode Grapher Calculator "Activity Monitor" "TextEdit" Mail Calendar Notes Preview "QuickTime Player" "System Preferences")
	@for app in $(TEST_APPS); do \
		pkill -9 "$$app" 2>/dev/null || true; \
		done
	@printf "$(GREEN)Done$(RESET): All test applications force quit and uninstalled\n"

# Clean build files
clean: ## Remove build directory and artifacts
	@if [ -d $(BUILD_DIR) ]; then \
		if [ -n "$$SUDO_USER" ] || [ "$$(id -u)" = "0" ]; then \
			rm -rf $(BUILD_DIR); \
		else \
			rm -rf $(BUILD_DIR) 2>/dev/null || sudo rm -rf $(BUILD_DIR); \
		fi; \
	fi
	@rm -f $(DUMP_WHITELIST_SOURCE) $(WINDOW_DUMP_WHITELIST_NAME)
	@sudo rm -f $(DUMP_INSTALL_PATH) $(DUMP_WHITELIST_DEST) 2>/dev/null || true
	@sudo rm -f $(WINDOW_DUMP_INSTALL_PATH) $(WINDOW_DUMP_WHITELIST_DEST) 2>/dev/null || true
	@rm -rf $(GUI_DIR)/ASConfigurator.app 2>/dev/null || true
	@printf "$(GREEN)Cleaned$(RESET) build directory and removed dump dylibs and whitelists\n"

# Uninstall
uninstall: ## Uninstall dylib, CLI, blacklist, and all dump dylibs
	@sudo rm -f $(INSTALL_PATH)
	@sudo rm -f $(CLI_INSTALL_PATH)
	@sudo rm -f $(CLI_INSTALL_DIR)/$(HELPER_NAME)
	@sudo rm -rf /Applications/$(GUI_APP)
	@sudo rm -rf /Applications/ASConfigurator.app
	@CURRENT_USER=$${SUDO_USER:-$$USER}; \
	CURRENT_UID=$$(id -u "$$CURRENT_USER"); \
	sudo launchctl bootout gui/$$CURRENT_UID /Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist 2>/dev/null || sudo -u "$$CURRENT_USER" launchctl unload /Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist 2>/dev/null || true; \
	sudo launchctl bootout gui/$$CURRENT_UID /Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist 2>/dev/null || sudo -u "$$CURRENT_USER" launchctl unload /Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist 2>/dev/null || true
	sudo launchctl bootout system /Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist 2>/dev/null || true
	@sudo launchctl bootout system /Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist 2>/dev/null || true
	sudo pkill -9 sharpener-helper 2>/dev/null || true; \
	sudo pkill -9 "$(GUI_APP_NAME)" 2>/dev/null || true; \
	sudo pkill -9 "ASConfigurator" 2>/dev/null || true
	@sudo rm -f /Library/LaunchAgents/com.aspauldingcode.sharpener.helper.plist
	@sudo rm -f /Library/LaunchAgents/com.aspauldingcode.asconfigurator.plist
	@sudo rm -f $(BLACKLIST_DEST)
	# Also remove old whitelist if present (transition cleanup)
	@sudo rm -f $(INSTALL_DIR)/lib$(PROJECT).dylib.whitelist 2>/dev/null || true
	@sudo rm -f $(INSTALL_DIR)/lib$(PROJECT).dylib.blacklist 2>/dev/null || true
	@sudo rm -f $(DUMP_INSTALL_PATH)
	@sudo rm -f $(DUMP_WHITELIST_DEST)
	@sudo rm -f $(WINDOW_DUMP_INSTALL_PATH)
	@sudo rm -f $(WINDOW_DUMP_WHITELIST_DEST)
	@printf "$(YELLOW)Uninstalled$(RESET) $(BOLD)%s$(RESET), $(BOLD)%s$(RESET), blacklist, and all dump dylibs\n" "$(DYLIB_NAME)" "$(CLI_NAME)"
	@printf "$(YELLOW)Restarting Dock$(RESET) to unload dylib...\n"
	@pkill -9 "Dock" 2>/dev/null || true

installer: ## Create a .pkg installer
	@printf "$(BOLD)$(CYAN)Packaging$(RESET) Apple Sharpener into a .pkg installer\n"
	./scripts/create_installer.sh

# Build dock dump dylib

$(BUILD_DIR)/$(DUMP_DYLIB_NAME): $(DUMP_SOURCE)
	@mkdir -p $(BUILD_DIR)/src/sharpener/Dock
	$(CC) $(CFLAGS) $(ARCHS) -DDOCK_DUMP_DIR="\"$(shell pwd)\"" -c $(DUMP_SOURCE) -o $(DUMP_OBJECT)
	$(CC) $(DYLIB_FLAGS) $(ARCHS) $(DUMP_OBJECT) -o $@ \
		-F$(FRAMEWORK_PATH) \
		-F$(PRIVATE_FRAMEWORK_PATH) \
		$(PUBLIC_FRAMEWORKS) \
		-L$(SDKROOT)/usr/lib
	@printf "$(GREEN)Built$(RESET) $(BOLD)%s$(RESET)\n" "$(DUMP_DYLIB_NAME)"

# Install and run dock dump
dumpdock: $(BUILD_DIR)/$(DUMP_DYLIB_NAME) ## Build, install dock dump dylib and restart Dock
	@printf "$(BOLD)$(CYAN)Installing$(RESET) dock dump dylib to $(BOLD)%s$(RESET)\n" "$(INSTALL_DIR)"
	@sudo mkdir -p $(INSTALL_DIR)
	@sudo install -m 755 $(BUILD_DIR)/$(DUMP_DYLIB_NAME) $(DUMP_INSTALL_PATH)
	@if [ -f $(DUMP_WHITELIST_SOURCE) ]; then \
		sudo cp $(DUMP_WHITELIST_SOURCE) $(DUMP_WHITELIST_DEST); \
		sudo chmod 644 $(DUMP_WHITELIST_DEST); \
		printf "$(GREEN)Installed$(RESET) whitelist: $(BOLD)%s$(RESET)\n" "$(DUMP_WHITELIST_SOURCE)"; \
		else \
		printf "$(YELLOW)Warning$(RESET): %s not found\n" "$(DUMP_WHITELIST_SOURCE)"; \
		fi
	@printf "$(YELLOW)Killing Dock$(RESET) to reload with dump dylib...\n"
	@pkill -9 "Dock" 2>/dev/null || true
	@sleep 2
	@printf "$(GREEN)Dock restarted$(RESET). Check Console.app or dock_layers_dump.txt in repo root for layer information\n"
	@echo "To remove the dump dylib, run: sudo rm $(DUMP_INSTALL_PATH) $(DUMP_WHITELIST_DEST) && pkill -9 Dock"

.PHONY: all build install clean uninstall installer dumpdock test

# Build window dump dylib (generic, works with any app)
# Usage: make dumpwindow APP="app_name_or_bundle_id"
# Example: make dumpwindow APP="zoom.us" or make dumpwindow APP="Zoom"
$(BUILD_DIR)/$(WINDOW_DUMP_DYLIB_NAME): $(WINDOW_DUMP_SOURCE)
	@if [ -z "$(APP)" ]; then \
		echo "Error: APP argument is required. Usage: make dumpwindow APP=\"app_name_or_bundle_id\""; \
		echo "Example: make dumpwindow APP=\"zoom.us\" or make dumpwindow APP=\"Zoom\""; \
		exit 1; \
	fi
	@mkdir -p $(BUILD_DIR)/src/sharpener/Windows
	@echo "Building $(WINDOW_DUMP_DYLIB_NAME) for app: $(APP)..."
	$(CC) $(CFLAGS) $(ARCHS) -DWINDOW_DUMP_DIR="\"$(shell pwd)\"" -DAPP_IDENTIFIER="\"$(APP)\"" -c $(WINDOW_DUMP_SOURCE) -o $(WINDOW_DUMP_OBJECT)
	$(CC) $(DYLIB_FLAGS) $(ARCHS) $(WINDOW_DUMP_OBJECT) -o $@ \
		-F$(FRAMEWORK_PATH) \
		-F$(PRIVATE_FRAMEWORK_PATH) \
		$(PUBLIC_FRAMEWORKS) \
		-L$(SDKROOT)/usr/lib
	@echo "Built $(WINDOW_DUMP_DYLIB_NAME) for app: $(APP)"

# Generate whitelist file for the target app
$(WINDOW_DUMP_WHITELIST_NAME): $(BUILD_DIR)/$(WINDOW_DUMP_DYLIB_NAME)
	@if [ -z "$(APP)" ]; then \
		echo "Error: APP argument is required."; \
		exit 1; \
	fi
	@echo "Generating whitelist for app: $(APP)..."
	@rm -f $(WINDOW_DUMP_WHITELIST_NAME)
	@echo "$(APP)" > $(WINDOW_DUMP_WHITELIST_NAME)
	@# Try to find bundle ID if APP is an app name
	@APP_PATH=$$(mdfind "kMDItemKind == 'Application' && (kMDItemDisplayName == '$(APP)' || kMDItemFSName == '$(APP).app')" 2>/dev/null | head -1); \
	if [ -n "$$APP_PATH" ] && [ -d "$$APP_PATH" ]; then \
		BUNDLE_ID=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$$APP_PATH/Contents/Info.plist" 2>/dev/null); \
		if [ -n "$$BUNDLE_ID" ]; then \
			echo "$$BUNDLE_ID" >> $(WINDOW_DUMP_WHITELIST_NAME); \
			echo "Found bundle ID: $$BUNDLE_ID"; \
		fi; \
		PROCESS_NAME=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$$APP_PATH/Contents/Info.plist" 2>/dev/null); \
		if [ -n "$$PROCESS_NAME" ] && [ "$$PROCESS_NAME" != "$(APP)" ]; then \
			echo "$$PROCESS_NAME" >> $(WINDOW_DUMP_WHITELIST_NAME); \
			echo "Found process name: $$PROCESS_NAME"; \
		fi; \
	fi
	@echo "" >> $(WINDOW_DUMP_WHITELIST_NAME)
	@echo "Generated whitelist: $(WINDOW_DUMP_WHITELIST_NAME)"

# Install window dump dylib and launch target app
# Usage: make dumpwindow APP="app_name_or_bundle_id"
dumpwindow: $(BUILD_DIR)/$(WINDOW_DUMP_DYLIB_NAME) $(WINDOW_DUMP_WHITELIST_NAME) ## Build, install window dump dylib for specified app (requires APP="app_name_or_bundle_id")
	@if [ -z "$(APP)" ]; then \
		echo "Error: APP argument is required. Usage: make dumpwindow APP=\"app_name_or_bundle_id\""; \
		echo "Example: make dumpwindow APP=\"zoom.us\" or make dumpwindow APP=\"Zoom\""; \
		exit 1; \
	fi
	@echo "Updating whitelist for app: $(APP)..."
	@rm -f $(WINDOW_DUMP_WHITELIST_NAME)
	@echo "$(APP)" > $(WINDOW_DUMP_WHITELIST_NAME)
	@APP_PATH=$$(mdfind "kMDItemKind == 'Application' && (kMDItemDisplayName == '$(APP)' || kMDItemFSName == '$(APP).app')" 2>/dev/null | head -1); \
	if [ -n "$$APP_PATH" ] && [ -d "$$APP_PATH" ]; then \
		BUNDLE_ID=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$$APP_PATH/Contents/Info.plist" 2>/dev/null); \
		if [ -n "$$BUNDLE_ID" ]; then \
			echo "$$BUNDLE_ID" >> $(WINDOW_DUMP_WHITELIST_NAME); \
		fi; \
		PROCESS_NAME=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$$APP_PATH/Contents/Info.plist" 2>/dev/null); \
		if [ -n "$$PROCESS_NAME" ] && [ "$$PROCESS_NAME" != "$(APP)" ]; then \
			echo "$$PROCESS_NAME" >> $(WINDOW_DUMP_WHITELIST_NAME); \
		fi; \
	fi
	@echo "" >> $(WINDOW_DUMP_WHITELIST_NAME)
	@echo "Installing $(WINDOW_DUMP_DYLIB_NAME) for app: $(APP)..."
	@sudo mkdir -p $(INSTALL_DIR)
	@sudo install -m 755 $(BUILD_DIR)/$(WINDOW_DUMP_DYLIB_NAME) $(WINDOW_DUMP_INSTALL_PATH)
	@sudo cp $(WINDOW_DUMP_WHITELIST_NAME) $(WINDOW_DUMP_WHITELIST_DEST)
	@sudo chmod 644 $(WINDOW_DUMP_WHITELIST_DEST)
	@echo "Installed whitelist: $(WINDOW_DUMP_WHITELIST_NAME)"
	@echo "Killing $(APP) to reload with dump dylib..."
	@pkill -9 -f "$(APP)" 2>/dev/null || true
	@sleep 2
	@echo "Launching $(APP)..."
	@APP_PATH=$$(mdfind "kMDItemKind == 'Application' && (kMDItemDisplayName == '$(APP)' || kMDItemFSName == '$(APP).app')" 2>/dev/null | head -1); \
	if [ -n "$$APP_PATH" ] && [ -d "$$APP_PATH" ]; then \
		open "$$APP_PATH" 2>/dev/null && echo "Launched $(APP) from: $$APP_PATH"; \
	elif [ -d "/Applications/$(APP).app" ]; then \
		open "/Applications/$(APP).app" 2>/dev/null && echo "Launched $(APP) from /Applications/$(APP).app"; \
	else \
		open -a "$(APP)" 2>/dev/null || echo "Warning: Could not find $(APP) app. Please launch it manually."; \
	fi
	@echo "Waiting 10 seconds for $(APP) to initialize and generate dump..."
	@sleep 10
	@echo "Copying dump file to repo root..."
	@REPO_ROOT=$(shell pwd); \
	APP_SANITIZED=$$(echo "$(APP)" | sed 's/[^a-zA-Z0-9]/_/g'); \
	DUMP_FILE="$$APP_SANITIZED_window_dump.txt"; \
	if [ -f "/tmp/$$DUMP_FILE" ]; then \
		cp -f "/tmp/$$DUMP_FILE" "$$REPO_ROOT/$$DUMP_FILE"; \
		echo "Dump file copied from /tmp to: $$REPO_ROOT/$$DUMP_FILE"; \
		ls -lh "$$REPO_ROOT/$$DUMP_FILE"; \
	elif [ -f "$$REPO_ROOT/$$DUMP_FILE" ]; then \
		echo "Dump file already at: $$REPO_ROOT/$$DUMP_FILE"; \
		ls -lh "$$REPO_ROOT/$$DUMP_FILE"; \
	else \
		echo "Warning: Dump file not found. It may still be generating."; \
		echo "Check: $$REPO_ROOT/$$DUMP_FILE or /tmp/$$DUMP_FILE"; \
	fi
	@echo ""
	@echo "Window dump complete! Check dump file in repo root."
	@echo "To remove the dump dylib, run: make clean"



help: ## Show this help
	@echo "Available make targets:"
	@grep -E '^[a-zA-Z0-9_.-]+:.*##' $(MAKEFILE_LIST) | sed 's/^\([^:]*\):.*##\s*\(.*\)/  \1|\2/' | awk -F'|' '{printf "  %-20s %s\n", $$1, $$2}'

.PHONY: all build clean install test end-test uninstall installer help dumpdock dumpwindow

# Debug Finder with Apple Sharpener injected
debug-finder: all
	@echo "Killing Finder..."
	@pkill -9 Finder || true
	@sleep 1
	@echo "Launching Finder with libapple_sharpener.dylib injected..."
	@DYLD_INSERT_LIBRARIES="$(shell pwd)/out/libapple_sharpener.dylib" /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder &
	@echo "Finder launched."
	@echo "Now open Xcode, go to Debug > Attach to Process > Finder."
	@echo "Then click the View Debugger icon (overlapping rectangles) to inspect the views."
