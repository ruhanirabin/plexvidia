# PLEXVIDIA

Plexvidia is an opinionated setup and verification script for Plex Media Server systems that use an NVIDIA GPU for hardware transcoding. It is written for Debian/Ubuntu-style systems commonly managed by Proxmox administrators.

Current release: `1.2.0`

## Scope

Run this script in the operating system where Plex Media Server is installed. For most Proxmox environments, that means the Ubuntu or Debian VM that owns the passed-through GPU, not the Proxmox VE host.

Supported admin models:

| Model | Status | Notes |
| --- | --- | --- |
| Ubuntu/Debian VM on Proxmox with PCI GPU passthrough | Supported | Preferred deployment model. |
| Proxmox VE host running Plex directly | Supported with care | The script detects Proxmox headers, but changing drivers on the host can affect other workloads. Snapshot/back up first. |
| Privileged LXC with mapped NVIDIA devices | Advanced | Host and container driver/device alignment is your responsibility. Validate `nvidia-smi` before changing Plex settings. |
| Docker-only Plex | Not supported | Run NVIDIA Container Toolkit and Plex container configuration separately. |
| Non-systemd systems | Not supported | The script manages systemd services. |

## What It Changes

By default, `plexvidia.sh`:

- Installs `nvidia-driver-535`, DKMS, build tools, and kernel headers when needed.
- Uses `pve-headers-$(uname -r)` on Proxmox-style kernels, otherwise `linux-headers-$(uname -r)`.
- Holds the selected NVIDIA driver package with `apt-mark hold`.
- Creates or updates `/etc/systemd/system/nvidia-persistenced-custom.service`.
- Backs up Plex `Preferences.xml` and sets `TranscoderTempDirectory="/dev/shm"`.
- Restarts `plexmediaserver.service`.
- Writes logs to `/var/log/plex-nvidia-setup.log`.

Clean mode additionally stops Plex, purges `nvidia*` packages, runs `apt autoremove --purge`, removes local NVIDIA modprobe/module config, and removes the custom persistence service. Clean mode no longer deletes Plex preferences.

## Prerequisites

- Root shell access in the Plex OS.
- Internet access and working `apt` repositories.
- Plex Media Server installed and started at least once.
- NVIDIA GPU visible to the Plex OS.
- Secure Boot disabled, or NVIDIA modules otherwise signed/enrolled by the admin.
- A VM snapshot or host backup before running clean mode or changing host-level drivers.

Preflight checks:

```bash
cat /etc/os-release
uname -r
systemctl status plexmediaserver --no-pager
lspci -nn | grep -i nvidia
nvidia-smi
df -h /dev/shm
mokutil --sb-state 2>/dev/null || true
apt-cache policy nvidia-driver-535
```

For Proxmox VM passthrough, validate IOMMU/VT-d or AMD-Vi, OVMF/UEFI settings, PCIe GPU passthrough, and that the GPU is visible inside the guest before running this script.

## GPU Passthrough Preflight

Plexvidia can check whether GPU passthrough looks correct from inside the Plex OS:

```bash
sudo ./plexvidia.sh --preflight
```

This checks for:

- NVIDIA PCI devices with `lspci`.
- Kernel driver details for visible NVIDIA PCI devices.
- `/dev/nvidia*` device nodes.
- `/dev/dri/renderD*` render devices.
- Whether `nvidia-smi` is installed and can communicate with the GPU.
- Plex service and preferences file presence.
- The configured transcode directory and available space.

Limits: the guest cannot prove every Proxmox host setting. If preflight does not see a GPU, fix passthrough on the Proxmox side before installing drivers in the guest.

For a Proxmox VM, check:

- Host BIOS has VT-d/IOMMU or AMD-Vi enabled.
- Proxmox host kernel has IOMMU enabled.
- The VM uses the expected BIOS/machine settings for the GPU, commonly OVMF/UEFI and PCIe.
- The PCI device is attached in the VM Hardware tab.
- `All Functions` is enabled when the GPU audio/function device must pass through with the GPU.
- The GPU is not claimed by the wrong host driver when it should be bound for passthrough.
- Inside the VM, `lspci -nn | grep -i nvidia` shows the GPU.

For LXC, check that the host NVIDIA stack works first, then map the required `/dev/nvidia*` and `/dev/dri/*` devices into the container and keep host/container NVIDIA userspace compatible.

## Install

```bash
chmod +x plexvidia.sh
sudo ./plexvidia.sh
```

Remote one-line install is possible because `plexvidia.sh` is self-contained. Review the script first when using this pattern:

```bash
curl -fsSL https://raw.githubusercontent.com/ruhanirabin/plexvidia/main/plexvidia.sh -o /tmp/plexvidia.sh
less /tmp/plexvidia.sh
sudo bash /tmp/plexvidia.sh --preflight
sudo bash /tmp/plexvidia.sh --driver-version 535
```

Direct `curl | bash` style execution also works:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ruhanirabin/plexvidia/main/plexvidia.sh)" plexvidia --preflight
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ruhanirabin/plexvidia/main/plexvidia.sh)" plexvidia --driver-version 535
```

For production runbooks, prefer a pinned release tag instead of `main` once tags are published:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ruhanirabin/plexvidia/v1.2.0/plexvidia.sh)" plexvidia --preflight
```

Remote install prerequisites: `curl`, working DNS/TLS, GitHub raw content access, and root privileges through `sudo` or a root shell. If `curl` is missing, install it first:

```bash
sudo apt-get update
sudo apt-get install -y curl
```

Common explicit run for Proxmox-admin runbooks:

```bash
sudo ./plexvidia.sh --driver-version 535 --transcode-dir /dev/shm
```

Unattended clean install:

```bash
sudo ./plexvidia.sh --clean --yes --driver-version 535
```

Verification-only run:

```bash
sudo ./plexvidia.sh --verify-only
```

Show all options:

```bash
./plexvidia.sh --help
```

## Configuration Options

| Option | Purpose |
| --- | --- |
| `--driver-version N` | Install `nvidia-driver-N`; defaults to `535`. |
| `--no-hold` | Skip `apt-mark hold` for the driver package. |
| `--power-limit W` | Opt in to `nvidia-smi -pl W`. No power limit is set by default. |
| `--transcode-dir PATH` | Set the Plex transcoder temp directory; defaults to `/dev/shm`. |
| `--skip-plex-prefs` | Do not edit Plex `Preferences.xml`. |
| `--skip-persistenced` | Do not create or restart the custom persistence service. |
| `--preflight` | Check GPU passthrough, Plex, Secure Boot, and transcode storage without installing. |
| `--clean` | Purge existing NVIDIA packages/config before installing. |
| `--yes` | Suppress prompts, primarily for `--clean`. |
| `--verify-only` | Inspect GPU, Plex service, and Plex logs without changing state. |

Environment overrides are also available: `PLEXVIDIA_LOG_FILE`, `PLEXVIDIA_DRIVER_VERSION`, `PLEXVIDIA_POWER_LIMIT`, `PLEXVIDIA_TRANSCODE_DIR`, `PLEXVIDIA_PLEX_SERVICE`, `PLEXVIDIA_PLEX_PREFS`, and `PLEXVIDIA_PLEX_LOG`.

## `/dev/shm` Warning

`/dev/shm` is RAM-backed. It can improve transcode latency, but Plex transcodes can fail if it is too small or if the VM/container is memory-constrained.

Check it before using the default:

```bash
df -h /dev/shm
```

Use a disk-backed path if RAM is limited:

```bash
sudo mkdir -p /var/lib/plexmediaserver/transcode
sudo chown plex:plex /var/lib/plexmediaserver/transcode
sudo ./plexvidia.sh --transcode-dir /var/lib/plexmediaserver/transcode
```

## Upgrade

Plexvidia follows Semantic Versioning:

- Major versions may change defaults or remove behavior.
- Minor versions add backward-compatible options or safer behavior.
- Patch versions fix bugs without changing the operating model.

To upgrade from an older script release:

```bash
git pull
./plexvidia.sh --version
sudo ./plexvidia.sh --preflight
sudo ./plexvidia.sh --verify-only
```

Then rerun with your desired options. Version `1.2.0` is intended to be idempotent for normal runs: it reuses an installed driver, refreshes the persistence service, backs up Plex preferences before editing, and reports verification state.

## Logging and Failure Handling

All normal script output is tee'd to `/var/log/plex-nvidia-setup.log`, including the banner, platform detection, preflight checks, package commands, Plex preference backups, service changes, warnings, and verification output.

Failure behavior:

- Required command failures exit non-zero and log the failed command and line number.
- `--preflight` exits non-zero when no guest-visible GPU signal is found.
- Missing Plex preferences or unsupported GPU power limits are warnings, not fatal install errors.
- `--verify-only` does not change system state.
- Clean mode requires `--clean`; unattended clean mode requires `--yes`.

## Error and Edge Case Handling

| Case | Script behavior | What to do |
| --- | --- | --- |
| Not run as root | Exits before writing `/var/log/plex-nvidia-setup.log`. | Run with `sudo` or from a root shell. |
| `curl` missing for remote install | Remote command cannot start. | Install `curl` with `sudo apt-get install -y curl`, or download the script another way. |
| GitHub raw URL unavailable | Remote command cannot start. | Check DNS/proxy/firewall, or use a locally downloaded copy. |
| No NVIDIA PCI device visible | `--preflight` warns and exits non-zero. | Fix Proxmox passthrough before installing guest drivers. |
| `lspci` missing | Preflight warns and continues with other signals. | Install `pciutils` for better passthrough diagnostics. |
| `nvidia-smi` missing before install | Preflight logs that it is not installed yet. | This is normal before driver installation if `lspci` shows the GPU. |
| `nvidia-smi` installed but failing | Warning in preflight/verify. | Check Secure Boot, DKMS build logs, matching kernel headers, and LXC device mapping. |
| Secure Boot enabled | Fatal error. | Disable Secure Boot or sign/enroll NVIDIA modules. |
| Kernel headers unavailable | Package install fails and logs the failed command. | Enable the right apt repositories and install matching `linux-headers-*` or `pve-headers-*`. |
| Apt lock or network failure | Package command exits non-zero and is logged. | Wait for other apt jobs to finish or fix network/repository issues, then rerun. |
| Plex not installed or not started once | Warning for missing service or `Preferences.xml`. | Install/start Plex, complete first-run setup, then rerun. |
| `/dev/shm` too small | Preflight shows filesystem size; install does not block. | Use `--transcode-dir` with a larger disk-backed path. |
| Power limit unsupported | Warning only. | Omit `--power-limit` or choose a supported value from `nvidia-smi -q -d POWER`. |
| Clean mode used accidentally | Interactive confirmation blocks unless `--yes` is supplied. | Restore VM snapshot or follow rollback steps if changes were applied. |

## Rollback

Prefer restoring the Proxmox VM snapshot if the driver change breaks the media server. Manual rollback commands:

```bash
sudo apt-mark unhold nvidia-driver-535 || true
sudo systemctl disable --now nvidia-persistenced-custom.service || true
sudo rm -f /etc/systemd/system/nvidia-persistenced-custom.service
sudo systemctl daemon-reload
```

Restore the latest Plex preferences backup created by plexvidia:

```bash
sudo ls -1t "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server"/Preferences.xml.plexvidia.bak.*
sudo cp -a "/path/to/Preferences.xml.plexvidia.bak.YYYYMMDDHHMMSS" "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml"
sudo systemctl restart plexmediaserver
```

Remove NVIDIA packages only if you intend to return to a non-NVIDIA setup:

```bash
sudo apt purge -y 'nvidia*'
sudo apt autoremove --purge -y
```

## Troubleshooting

GPU absent inside VM:

```bash
lspci -nn | grep -i nvidia
sudo ./plexvidia.sh --preflight
```

If empty, fix Proxmox passthrough before running plexvidia.

Driver loaded but Plex not using hardware transcoding:

```bash
nvidia-smi
sudo ./plexvidia.sh --verify-only
sudo journalctl -u plexmediaserver --no-pager -n 100
```

Also confirm Plex hardware transcoding is enabled in Plex settings and that your Plex license/support model allows it.

DKMS or header install fails:

```bash
uname -r
apt-cache policy "linux-headers-$(uname -r)" "pve-headers-$(uname -r)"
```

Install the matching headers for the running kernel, reboot if needed, then rerun.

Power limit fails:

```bash
nvidia-smi -q -d POWER
```

Some GPUs or virtualized configurations do not support power-limit changes. Omit `--power-limit`.

Package hold blocks future NVIDIA upgrades:

```bash
sudo apt-mark unhold nvidia-driver-535
```

Then rerun plexvidia with the desired `--driver-version`.

## Maintainers

Operational safety is part of the project. Any change to packages, paths, service names, destructive commands, supported platforms, or rollback behavior must update this README and `CHANGELOG.md`.
