# =============================================================================
# Makefile — install targets for cc-switcher/bash
# =============================================================================

.PHONY: install install-system help lint clean

# Default install prefix (user-space)
PREFIX ?= $(HOME)/.cc-switcher
DESTDIR ?=
SYSTEM_PREFIX ?= /usr/local

# Files to install
SRC_DIR := $(shell pwd)
INSTALL_DIR := $(DESTDIR)$(PREFIX)
SYSTEM_INSTALL_DIR := $(DESTDIR)$(SYSTEM_PREFIX)/etc/cc-switcher

LIB_FILES := $(SRC_DIR)/lib/core.sh \
	$(SRC_DIR)/lib/providers.sh \
	$(SRC_DIR)/lib/codex.sh \
	$(SRC_DIR)/lib/pricing.sh \
	$(SRC_DIR)/lib/doctor.sh \
	$(SRC_DIR)/lib/completers.sh \
	$(SRC_DIR)/lib/usage.sh \
	$(SRC_DIR)/lib/update-check.sh

DATA_FILES := $(SRC_DIR)/data/providers.json

INSTALL_FILES := $(SRC_DIR)/cc-switcher.sh $(LIB_FILES) $(DATA_FILES)

# =============================================================================
# Help
# =============================================================================

help:
	@echo "cc-switcher bash install targets"
	@echo ""
	@echo "  make install           Install to ~/.cc-switcher (default)"
	@echo "  make install-system    Install to /usr/local/etc/cc-switcher"
	@echo "  make clean             Remove installed files"
	@echo ""

# =============================================================================
# User install — ~/.cc-switcher
# =============================================================================

install: $(INSTALL_FILES)
	@echo "Installing cc-switcher to $(INSTALL_DIR) ..."
	@mkdir -p "$(INSTALL_DIR)"
	@mkdir -p "$(INSTALL_DIR)/lib"
	@mkdir -p "$(INSTALL_DIR)/data"
	@cp $(SRC_DIR)/cc-switcher.sh "$(INSTALL_DIR)/"
	@cp $(LIB_FILES) "$(INSTALL_DIR)/lib/"
	@cp $(DATA_FILES) "$(INSTALL_DIR)/data/"
	@echo "Installed. Add to ~/.bashrc:"
	@echo ""
	@echo "  # Source cc-switcher"
	@echo "  if [ -f \"$(INSTALL_DIR)/cc-switcher.sh\" ]; then"
	@echo "    source \"$(INSTALL_DIR)/cc-switcher.sh\""
	@echo "  fi"
	@echo ""
	@echo "Then: source ~/.bashrc"
	@echo ""

# =============================================================================
# System install — /usr/local/etc/cc-switcher (from /etc/profile.d/)
# =============================================================================

install-system: $(INSTALL_FILES)
	@echo "Installing cc-switcher to $(SYSTEM_INSTALL_DIR) ..."
	@mkdir -p "$(SYSTEM_INSTALL_DIR)/lib"
	@mkdir -p "$(SYSTEM_INSTALL_DIR)/data"
	@cp $(SRC_DIR)/cc-switcher.sh "$(SYSTEM_INSTALL_DIR)/"
	@cp $(LIB_FILES) "$(SYSTEM_INSTALL_DIR)/lib/"
	@cp $(DATA_FILES) "$(SYSTEM_INSTALL_DIR)/data/"
	@echo "Installed system-wide. Ensure /etc/profile.d/cc-switcher.sh exists:"
	@echo ""
	@echo "  # /etc/profile.d/cc-switcher.sh"
	@echo "  if [ -f \"$(SYSTEM_INSTALL_DIR)/cc-switcher.sh\" ]; then"
	@echo "    source \"$(SYSTEM_INSTALL_DIR)/cc-switcher.sh\""
	@echo "  fi"
	@echo ""

# =============================================================================
# Clean
# =============================================================================

clean:
	@echo "Removing $(INSTALL_DIR) ..."
	@rm -rf "$(INSTALL_DIR)"
	@echo "Done."