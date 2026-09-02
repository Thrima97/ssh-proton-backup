# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-02

### Added

- Encrypted, change-based backup of `~/.ssh` to Proton Drive via the official CLI
- systemd user path unit (backup shortly after keys change) and daily 20:00 timer
- Restore script that refuses to extract into `~/.ssh`
- Installer that downloads Proton Drive CLI 0.8.0 and verifies published SHA-512 checksums
- Makefile (`install`, `uninstall`, `check`, `backup`, `restore`)

[0.1.0]: https://github.com/Thrima97/ssh-proton-backup/releases/tag/v0.1.0
