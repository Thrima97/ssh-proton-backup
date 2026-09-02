.DEFAULT_GOAL := help

INSTALL_BIN  := $(HOME)/.local/bin
INSTALL_LIB  := $(HOME)/.local/lib/ssh-proton-backup
CONFIG_DIR   := $(HOME)/.config/ssh-backup
WORK_DIR     := $(HOME)/.local/state/ssh-backups
SYSTEMD_DIR  := $(HOME)/.config/systemd/user

BACKUP_BIN  := $(INSTALL_BIN)/ssh-proton-backup.sh
RESTORE_BIN := $(INSTALL_BIN)/ssh-proton-restore.sh
SCRIPTS     := install.sh ssh-proton-backup.sh ssh-proton-restore.sh lib/env.sh

.PHONY: help install uninstall uninstall-purge check backup backup-force restore

help:
	@printf '%s\n' \
		'ssh-proton-backup' \
		'' \
		'  make install           Install scripts, Proton Drive CLI, and systemd units' \
		'  make uninstall         Remove scripts and systemd units (keep config and archives)' \
		'  make uninstall-purge   Uninstall and delete local config and encrypted archives' \
		'  make check             Run shellcheck on the scripts' \
		'  make backup            Run a change-based backup (installed script, else local)' \
		'  make backup-force      Force a backup even if ~/.ssh has not changed' \
		'  make restore ARCHIVE=path [DEST=dir]' \
		'                         Decrypt an archive (never into ~/.ssh)' \
		'' \
		'Non-interactive install (skip the passphrase prompt):' \
		'  SKIP_PASSPHRASE=1 make install'

install:
	@chmod +x install.sh ssh-proton-backup.sh ssh-proton-restore.sh
	./install.sh

uninstall:
	@echo "Stopping and disabling systemd user units..."
	-systemctl --user disable --now ssh-proton-backup.timer >/dev/null 2>&1
	-systemctl --user disable --now ssh-proton-backup.path >/dev/null 2>&1
	-systemctl --user disable --now ssh-proton-backup.service >/dev/null 2>&1
	rm -f \
		"$(SYSTEMD_DIR)/ssh-proton-backup.service" \
		"$(SYSTEMD_DIR)/ssh-proton-backup.timer" \
		"$(SYSTEMD_DIR)/ssh-proton-backup.path"
	-systemctl --user daemon-reload >/dev/null 2>&1
	rm -f "$(BACKUP_BIN)" "$(RESTORE_BIN)"
	rm -rf "$(INSTALL_LIB)"
	@echo "Removed scripts and systemd units."
	@echo "Kept $(CONFIG_DIR) and $(WORK_DIR)."
	@echo "Run 'make uninstall-purge' to delete those as well."

uninstall-purge: uninstall
	rm -rf "$(CONFIG_DIR)" "$(WORK_DIR)"
	@echo "Removed $(CONFIG_DIR) and $(WORK_DIR)."
	@echo "Proton Drive copies were not deleted."

check:
	@command -v shellcheck >/dev/null 2>&1 || { \
		echo "ERROR: shellcheck is not installed." >&2; \
		echo "Install it with: sudo apt-get install -y shellcheck" >&2; \
		exit 1; \
	}
	shellcheck $(SCRIPTS)

backup:
	@if [ -x "$(BACKUP_BIN)" ]; then \
		"$(BACKUP_BIN)"; \
	else \
		./ssh-proton-backup.sh; \
	fi

backup-force:
	@if [ -x "$(BACKUP_BIN)" ]; then \
		"$(BACKUP_BIN)" --force; \
	else \
		./ssh-proton-backup.sh --force; \
	fi

restore:
	@if [ -z "$(ARCHIVE)" ]; then \
		echo "ERROR: ARCHIVE is required. Example:" >&2; \
		echo "  make restore ARCHIVE=~/Downloads/host_ssh_DATE.tar.gz.gpg DEST=~/ssh-restore" >&2; \
		exit 1; \
	fi
	@if [ -x "$(RESTORE_BIN)" ]; then \
		if [ -n "$(DEST)" ]; then \
			"$(RESTORE_BIN)" "$(ARCHIVE)" "$(DEST)"; \
		else \
			"$(RESTORE_BIN)" "$(ARCHIVE)"; \
		fi; \
	else \
		if [ -n "$(DEST)" ]; then \
			./ssh-proton-restore.sh "$(ARCHIVE)" "$(DEST)"; \
		else \
			./ssh-proton-restore.sh "$(ARCHIVE)"; \
		fi; \
	fi
