# Apple Sharpener Makefile (Slim Version)
PROJECT := apple_sharpener
VERSION := $(shell cat VERSION 2>/dev/null || echo "0.0.1")
BUILD_DIR := build
SOURCE_DIR := src
GUI_DIR := $(SOURCE_DIR)/gui/ASConfigurator
INSTALL_DIR := /var/ammonia/core/tweaks
BIN_DIR := /usr/local/bin

# Compiler & Flags
SDKROOT := $(shell xcrun --show-sdk-path)
CC := xcrun -sdk macosx clang
ARCHS := -arch x86_64 -arch arm64 -arch arm64e
COMMON_FLAGS := -Wall -Wextra -O2 -fobjc-arc -isysroot $(SDKROOT) -IZKSwizzle -I$(SOURCE_DIR)/sharpener $(ARCHS) -DAPPLE_SHARPENER_LOGS
DYLIB_FLAGS := -dynamiclib -install_name $(INSTALL_DIR)/lib$(PROJECT).dylib -F$(SDKROOT)/System/Library/PrivateFrameworks -undefined dynamic_lookup
FRAMEWORKS := -framework Foundation -framework AppKit -framework QuartzCore -framework Cocoa -framework CoreFoundation -framework IOSurface

# Colors & UI
CYAN := \033[1;36m
GREEN := \033[1;32m
YELLOW := \033[1;33m
RESET := \033[0m

# Artifacts
DYLIB := $(BUILD_DIR)/lib$(PROJECT).dylib
CLI := $(BUILD_DIR)/sharpener
HELPER := $(BUILD_DIR)/sharpener-helper
GUI_BIN := $(BUILD_DIR)/sharpener-configurator

# Sources
DYLIB_SRCS := $(SOURCE_DIR)/sharpener/sharpener.m $(SOURCE_DIR)/sharpener/sharpener_log.m $(SOURCE_DIR)/sharpener/Windows/window.m \
              $(SOURCE_DIR)/sharpener/Windows/window_chrome_roles.m $(SOURCE_DIR)/sharpener/Dock/dock.m ZKSwizzle/ZKSwizzle.m
DYLIB_OBJS := $(DYLIB_SRCS:%.m=$(BUILD_DIR)/%.o)

.DEFAULT_GOAL := all
.PHONY: all install clean uninstall test configurator help

all: $(DYLIB) $(CLI) $(HELPER) configurator ## Build all components

$(BUILD_DIR)/%.o: %.m
	@mkdir -p $(dir $@)
	$(CC) $(COMMON_FLAGS) -c $< -o $@

$(DYLIB): $(DYLIB_OBJS)
	$(CC) $(DYLIB_FLAGS) $(ARCHS) $^ -o $@ $(FRAMEWORKS)
	codesign -f -s - $@
	@printf "$(GREEN)Built and signed$(RESET) dylib: $(CYAN)$@$(RESET)\n"

$(CLI): $(SOURCE_DIR)/sharpener/clitool.m $(SOURCE_DIR)/sharpener/sharpener_cf_prefs.m
	$(CC) $(COMMON_FLAGS) $^ -o $@ -DAPPLE_SHARPENER_VERSION="\"$(VERSION)\"" -framework Foundation -framework CoreFoundation
	@printf "$(GREEN)Built$(RESET) CLI: $(CYAN)$@$(RESET)\n"

$(HELPER): $(SOURCE_DIR)/helper/sharpener_helper.m $(SOURCE_DIR)/sharpener/sharpener_log.m
	$(CC) $(COMMON_FLAGS) $^ -o $@ -framework Foundation
	@printf "$(GREEN)Built$(RESET) Helper: $(CYAN)$@$(RESET)\n"

configurator: ## Build GUI Configurator
	@printf "$(YELLOW)Building$(RESET) configurator...\n"
	cd $(GUI_DIR) && swift build -c release
	cp -f $(GUI_DIR)/.build/release/AppleSharpenerConfigurator $(GUI_BIN)
	@printf "$(GREEN)Built$(RESET) GUI: $(CYAN)$(GUI_BIN)$(RESET)\n"

install: all ## Install everything to system
	@printf "$(YELLOW)Installing$(RESET) Apple Sharpener suite...\n"
	sudo mkdir -p $(INSTALL_DIR) $(BIN_DIR)
	sudo install -m 755 $(DYLIB) $(INSTALL_DIR)
	sudo install -m 755 $(CLI) $(HELPER) $(GUI_BIN) $(BIN_DIR)
	# Service Registration
	CUR_USER=$${SUDO_USER:-$$USER}; CUR_UID=$$(id -u "$$CUR_USER"); USER_HOME=$$(eval echo "~$$CUR_USER"); \
	mkdir -p "$$USER_HOME/Library/LaunchAgents"; \
	for p in com.aspauldingcode.sharpener.helper.plist com.aspauldingcode.asconfigurator.plist; do \
		src=$$(find src -name "$$p"); \
		cp "$$src" "$$USER_HOME/Library/LaunchAgents/"; \
		chown "$$CUR_USER" "$$USER_HOME/Library/LaunchAgents/$$p"; \
		sudo -u "$$CUR_USER" launchctl bootout gui/$$CUR_UID "$$USER_HOME/Library/LaunchAgents/$$p" 2>/dev/null || true; \
		sudo -u "$$CUR_USER" launchctl bootstrap gui/$$CUR_UID "$$USER_HOME/Library/LaunchAgents/$$p" 2>/dev/null || true; \
	done
	@pkill -9 "Dock" 2>/dev/null || true
	@printf "$(GREEN)Installed$(RESET) and restarted Dock.\n"

uninstall: ## Uninstall everything
	sudo rm -f $(INSTALL_DIR)/lib$(PROJECT).dylib $(BIN_DIR)/sharpener $(BIN_DIR)/sharpener-helper $(BIN_DIR)/sharpener-configurator
	CUR_USER=$${SUDO_USER:-$$USER}; CUR_UID=$$(id -u "$$CUR_USER"); USER_HOME=$$(eval echo "~$$CUR_USER"); \
	for p in com.aspauldingcode.sharpener.helper.plist com.aspauldingcode.asconfigurator.plist; do \
		sudo -u "$$CUR_USER" launchctl bootout gui/$$CUR_UID "$$USER_HOME/Library/LaunchAgents/$$p" 2>/dev/null || true; \
		rm -f "$$USER_HOME/Library/LaunchAgents/$$p"; \
	done
	pkill -9 sharpener-helper sharpener-configurator Dock 2>/dev/null || true
	@printf "$(YELLOW)Uninstalled$(RESET) suite.\n"

clean: ## Remove build artifacts
	rm -rf $(BUILD_DIR) $(GUI_DIR)/.build
	find . \( -name ".DS_Store" -o -name "*.log" -o -name "*_window_dump.txt" \) -delete
	@printf "$(GREEN)Cleaned$(RESET) project.\n"

test: install ## Install and relaunch test apps
	@printf "$(YELLOW)Restarting$(RESET) test applications...\n"
	@for app in Spotify Finder Safari Mail Notes Preview; do pkill -9 "$$app" 2>/dev/null || true; open -a "$$app" 2>/dev/null || true; done

installer: ## Create a .pkg installer
	@printf "$(CYAN)Packaging$(RESET) Apple Sharpener...\n"
	@./scripts/create_installer.sh

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_.-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
