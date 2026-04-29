# Changelog

All notable changes to Plexvidia are documented here.

Plexvidia follows Semantic Versioning.

## [1.2.0] - 2026-04-29

### Added

- Added `--preflight` to check guest-visible GPU passthrough signals before installing drivers or changing Plex settings.
- Added checks for NVIDIA PCI devices, kernel driver bindings, `/dev/nvidia*`, `/dev/dri/renderD*`, `nvidia-smi`, Plex service/preferences, and transcode storage.
- Added remote one-line installer documentation for raw GitHub execution, including safer download-review-run commands and pinned-tag guidance.
- Added logging/failure-handling documentation.
- Added error and edge case handling guidance for root access, missing `curl`/`lspci`, missing passthrough, Secure Boot, apt failures, Plex first-run state, `/dev/shm` sizing, and unsupported power limits.

### Changed

- Updated script version, README current release, and banner SemVer output to `1.2.0`.
- Improved warnings for incomplete passthrough, missing Plex files, unsupported power limits, and missing tools such as `lspci`.
- Expanded logging around backup creation, clean-mode file removal, systemd service writing, and command failures.
- Removed the Python helper dependency from Plex preference editing so raw `bash -c "$(curl ...)"` execution works reliably.

### Compatibility Notes

- `--preflight` exits non-zero when no usable guest-visible GPU signal is found.
- The preflight can identify missing guest-visible passthrough signals, but it cannot prove every Proxmox host-side setting from inside the VM or container.

## [1.1.0] - 2026-04-29

### Added

- Added `VERSION=1.1.0` plus `--version` and `--help` output.
- Added admin flags: `--driver-version`, `--no-hold`, `--power-limit`, `--skip-plex-prefs`, `--skip-persistenced`, `--transcode-dir`, `--verify-only`, `--clean`, and `--yes`.
- Added Proxmox-style kernel detection so driver installs use `pve-headers-$(uname -r)` when appropriate.
- Added Plex `Preferences.xml` backups before setting `TranscoderTempDirectory`.
- Added verification-only checks for `nvidia-smi`, Plex service status, and recent Plex hardware-transcode log lines.
- Added operator documentation for support scope, preflight checks, upgrade, rollback, `/dev/shm` risk, and troubleshooting.
- Added `AGENTS.md` maintainer guidance.

### Changed

- Reworked the script to require root instead of assuming `sudo` is installed.
- Removed background spinner execution so command failures propagate normally under `set -Eeuo pipefail`.
- Made GPU power limit opt-in instead of forcing `100W`.
- Made the NVIDIA driver branch configurable while keeping `535` as the default.
- Updated Plex preferences as a `Preferences` XML attribute instead of treating `TranscoderTempDirectory` as an XML element.
- Clean mode no longer deletes Plex `Preferences.xml`.

### Fixed

- Fixed verification paths that could exit early when Plex logs had no matching hardware-transcode lines.
- Fixed install behavior on Proxmox kernels where `linux-headers-$(uname -r)` is not the correct header package.
- Fixed repeated Plex preference edits creating duplicate or malformed transcode directory settings.

### Compatibility Notes

- Normal reruns are intended to be idempotent.
- Clean mode is still destructive to NVIDIA packages and NVIDIA config; snapshot first.
- The script is intended for Debian/Ubuntu-style Plex systems, especially Proxmox-managed VMs. Docker-only Plex and non-systemd hosts remain out of scope.

## [1.0.0] - 2026-04-29

### Added

- Initial script for installing NVIDIA driver `535`, configuring `nvidia-persistenced`, setting Plex transcode temp directory to `/dev/shm`, restarting Plex, and checking Plex logs.
