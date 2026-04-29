#!/usr/bin/env bash

set -Eeuo pipefail

VERSION="1.2.0"
LOG_FILE="${PLEXVIDIA_LOG_FILE:-/var/log/plex-nvidia-setup.log}"
DEFAULT_DRIVER_VERSION="535"
DRIVER_VERSION="${PLEXVIDIA_DRIVER_VERSION:-$DEFAULT_DRIVER_VERSION}"
POWER_LIMIT="${PLEXVIDIA_POWER_LIMIT:-}"
TRANSCODE_PATH="${PLEXVIDIA_TRANSCODE_DIR:-/dev/shm}"
PLEX_SERVICE="${PLEXVIDIA_PLEX_SERVICE:-plexmediaserver.service}"
PLEX_PREFS="${PLEXVIDIA_PLEX_PREFS:-/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml}"
PLEX_LOG="${PLEXVIDIA_PLEX_LOG:-/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Logs/Plex Media Server.log}"

CLEAN="false"
ASSUME_YES="false"
HOLD_DRIVER="true"
CONFIGURE_PERSISTENCED="true"
CONFIGURE_PLEX_PREFS="true"
VERIFY_ONLY="false"
PREFLIGHT_ONLY="false"

usage() {
  cat <<EOF
plexvidia ${VERSION}

Configures NVIDIA drivers and Plex hardware transcoding on Debian/Ubuntu-based
Plex systems, including Proxmox VE hosts, VMs, and privileged LXC guests.

Usage:
  sudo ./plexvidia.sh [options]

Options:
  --clean                 Purge existing NVIDIA packages and local NVIDIA config first.
  --yes                   Do not prompt; required for unattended runs with --clean.
  --driver-version N      Install nvidia-driver-N. Default: ${DEFAULT_DRIVER_VERSION}.
  --no-hold               Do not apt-mark hold the selected driver package.
  --power-limit W         Set GPU power limit in watts with nvidia-smi -pl.
  --skip-power-limit      Do not set a GPU power limit.
  --transcode-dir PATH    Set Plex TranscoderTempDirectory. Default: /dev/shm.
  --skip-plex-prefs       Do not edit Plex Preferences.xml.
  --skip-persistenced     Do not create/start the nvidia-persistenced service.
  --preflight             Check platform, GPU passthrough, Secure Boot, Plex, and /dev/shm only.
  --verify-only           Do not install or change settings; print current status.
  --version               Print version.
  -h, --help              Show this help.

Environment overrides:
  PLEXVIDIA_LOG_FILE, PLEXVIDIA_DRIVER_VERSION, PLEXVIDIA_POWER_LIMIT,
  PLEXVIDIA_TRANSCODE_DIR, PLEXVIDIA_PLEX_SERVICE, PLEXVIDIA_PLEX_PREFS,
  PLEXVIDIA_PLEX_LOG
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) CLEAN="true" ;;
    --yes|-y) ASSUME_YES="true" ;;
    --driver-version)
      [[ $# -ge 2 ]] || { echo "Missing value for --driver-version" >&2; exit 2; }
      DRIVER_VERSION="$2"
      shift
      ;;
    --no-hold) HOLD_DRIVER="false" ;;
    --power-limit)
      [[ $# -ge 2 ]] || { echo "Missing value for --power-limit" >&2; exit 2; }
      POWER_LIMIT="$2"
      shift
      ;;
    --skip-power-limit) POWER_LIMIT="" ;;
    --transcode-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --transcode-dir" >&2; exit 2; }
      TRANSCODE_PATH="$2"
      shift
      ;;
    --skip-plex-prefs) CONFIGURE_PLEX_PREFS="false" ;;
    --skip-persistenced) CONFIGURE_PERSISTENCED="false" ;;
    --preflight) PREFLIGHT_ONLY="true" ;;
    --verify-only) VERIFY_ONLY="true" ;;
    --version) echo "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: Run as root: sudo ./plexvidia.sh" >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'status=$?; log "ERROR: command failed with exit ${status} at line ${LINENO}: ${BASH_COMMAND}"; exit "$status"' ERR

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

run() {
  log "+ $*"
  "$@"
}

warn() {
  log "WARNING: $*"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run as root: sudo ./plexvidia.sh"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

print_banner() {
  # ASCII Header Banner
  cat <<EOF
██████╗ ██╗     ███████╗██╗  ██╗██╗   ██╗██╗██████╗ ██╗ █████╗
██╔══██╗██║     ██╔════╝╚██╗██╔╝██║   ██║██║██╔══██╗██║██╔══██╗
██████╔╝██║     █████╗   ╚███╔╝ ██║   ██║██║██║  ██║██║███████║
██╔═══╝ ██║     ██╔══╝   ██╔██╗ ╚██╗ ██╔╝██║██║  ██║██║██╔══██║
██║     ███████╗███████╗██╔╝ ██╗ ╚████╔╝ ██║██████╔╝██║██║  ██║
╚═╝     ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═════╝ ╚═╝╚═╝  ╚═╝
              GPU-Accelerated Plex Transcoding Setup
              aka: Plex NVIDIA Forge • v${VERSION}
          By Ruhani Rabin • https://github.com/ruhanirabin/plexvidia
EOF
}

confirm_clean() {
  if [[ "$CLEAN" != "true" || "$ASSUME_YES" == "true" ]]; then
    return
  fi

  read -r -p "Clean setup purges NVIDIA packages/config and stops Plex. Continue? [y/N]: " answer
  answer="${answer,,}"
  [[ "$answer" == "y" || "$answer" == "yes" ]] || fail "Clean setup cancelled."
}

is_proxmox_kernel() {
  command -v pveversion >/dev/null 2>&1 || [[ "$(uname -r)" == *"pve"* ]]
}

header_package() {
  if is_proxmox_kernel; then
    printf 'pve-headers-%s' "$(uname -r)"
  else
    printf 'linux-headers-%s' "$(uname -r)"
  fi
}

driver_package() {
  printf 'nvidia-driver-%s' "$DRIVER_VERSION"
}

detect_platform() {
  local os_name="unknown"
  local virt_type="unknown"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_name="${PRETTY_NAME:-$ID}"
  fi

  log "Plexvidia ${VERSION}"
  log "Platform: ${os_name}; kernel: $(uname -r)"
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    virt_type="$(systemd-detect-virt 2>/dev/null || true)"
    [[ -n "$virt_type" ]] || virt_type="bare-metal-or-undetected"
    log "Virtualization: ${virt_type}"
  fi
  if is_proxmox_kernel; then
    log "Detected Proxmox-style kernel/header packaging."
  fi
}

check_secure_boot() {
  if command -v mokutil >/dev/null 2>&1; then
    if mokutil --sb-state 2>/dev/null | grep -qi enabled; then
      fail "Secure Boot is enabled. Disable Secure Boot or enroll/sign NVIDIA modules before continuing."
    fi
    log "Secure Boot is not reported as enabled."
  else
    log "mokutil not found; skipping Secure Boot check."
  fi
}

check_gpu_presence() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi --query-gpu=name,driver_version --format=csv,noheader; then
      log "NVIDIA driver is loaded and the GPU is reachable through nvidia-smi."
    else
      warn "nvidia-smi exists but cannot communicate with the GPU. Check driver/DKMS status and device permissions."
    fi
    return
  fi

  if command -v lspci >/dev/null 2>&1 && lspci -nn | grep -qi nvidia; then
    log "NVIDIA PCI device detected; driver is not active yet."
    return
  fi

  if [[ -e /dev/nvidiactl || -e /dev/dri/renderD128 ]]; then
    log "GPU device nodes detected."
    return
  fi

  warn "No NVIDIA GPU was detected. On Proxmox, confirm PCI passthrough or LXC device mapping before installing drivers."
}

check_gpu_passthrough() {
  local found_gpu="false"

  log "Checking GPU passthrough signals visible from this OS."

  if command -v lspci >/dev/null 2>&1; then
    local pci_lines
    pci_lines="$(lspci -Dnn | grep -Ei 'NVIDIA|10de:' || true)"
    if [[ -n "$pci_lines" ]]; then
      found_gpu="true"
      log "NVIDIA PCI device visible:"
      printf '%s\n' "$pci_lines"

      local pci_ids
      pci_ids="$(printf '%s\n' "$pci_lines" | awk '{print $1}')"
      while IFS= read -r pci_id; do
        [[ -n "$pci_id" ]] || continue
        log "Kernel driver details for ${pci_id}:"
        lspci -Dnnk -s "$pci_id" || true
      done <<< "$pci_ids"
    else
      warn "No NVIDIA PCI device is visible to this OS."
    fi
  else
    warn "lspci is not installed; install pciutils to inspect PCI passthrough: apt-get install -y pciutils"
  fi

  if [[ -e /dev/nvidiactl || -e /dev/nvidia0 ]]; then
    found_gpu="true"
    log "NVIDIA character devices are present:"
    ls -l /dev/nvidia* 2>/dev/null || true
  else
    warn "No /dev/nvidia* devices are present yet. This is expected before a working NVIDIA driver, but not after installation."
  fi

  if compgen -G "/dev/dri/renderD*" >/dev/null; then
    log "DRI render devices are present:"
    ls -l /dev/dri/renderD* 2>/dev/null || true
  else
    warn "No /dev/dri/renderD* device found. Plex may not see a usable render device in some configurations."
  fi

  if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi >/dev/null 2>&1; then
      found_gpu="true"
      log "nvidia-smi can communicate with the GPU."
    else
      warn "nvidia-smi is installed but failed. Common causes: missing matching kernel headers, failed DKMS build, Secure Boot blocking modules, or incomplete LXC device mapping."
    fi
  else
    log "nvidia-smi is not installed yet."
  fi

  if [[ "$found_gpu" != "true" ]]; then
    warn "GPU passthrough is not proven from inside this OS."
    warn "For a Proxmox VM, check the VM Hardware tab for the PCI device, use OVMF/UEFI when required, enable PCIe and All Functions as needed, and verify IOMMU is enabled on the host."
    warn "For Proxmox LXC, map /dev/nvidia* and /dev/dri/* devices and keep host/container NVIDIA driver userspace compatible."
    return 1
  fi

  log "GPU passthrough preflight has at least one positive signal."
}

check_plex_preflight() {
  if systemctl list-unit-files "$PLEX_SERVICE" >/dev/null 2>&1; then
    log "Plex service exists: ${PLEX_SERVICE}"
  else
    warn "Plex service ${PLEX_SERVICE} was not found. Install/start Plex or set PLEXVIDIA_PLEX_SERVICE."
  fi

  if [[ -f "$PLEX_PREFS" ]]; then
    log "Plex preferences file exists: ${PLEX_PREFS}"
  else
    warn "Plex preferences file not found: ${PLEX_PREFS}. Start Plex once before editing preferences."
  fi

  if [[ -d "$TRANSCODE_PATH" ]]; then
    log "Transcode directory exists: ${TRANSCODE_PATH}"
    df -h "$TRANSCODE_PATH" || true
  else
    warn "Transcode directory does not exist: ${TRANSCODE_PATH}"
  fi
}

preflight() {
  local status=0
  detect_platform
  check_secure_boot || status=1
  check_gpu_passthrough || status=1
  check_plex_preflight || status=1

  if [[ "$status" -eq 0 ]]; then
    log "Preflight completed without blocking issues."
  else
    warn "Preflight found issues. Review the warnings above before installing or changing Plex settings."
  fi

  return "$status"
}

clean_nvidia() {
  log "Performing clean NVIDIA removal."
  systemctl stop "$PLEX_SERVICE" || warn "Could not stop ${PLEX_SERVICE}; continuing clean mode."
  run apt-get purge -y 'nvidia*'
  run apt-get autoremove --purge -y
  log "Removing local NVIDIA config and custom persistence service files."
  rm -rf /etc/X11/xorg.conf \
    /etc/modprobe.d/nvidia* \
    /lib/modprobe.d/nvidia* \
    /etc/modules-load.d/nvidia* \
    /etc/systemd/system/nvidia-persistenced-custom.service
  run systemctl daemon-reload
}

install_driver() {
  local driver_pkg
  local headers_pkg
  driver_pkg="$(driver_package)"
  headers_pkg="$(header_package)"

  if dpkg-query -W -f='${Status}' "$driver_pkg" 2>/dev/null | grep -q "install ok installed"; then
    log "${driver_pkg} is already installed."
  else
    run apt-get update
    run apt-get install -y dkms build-essential "$headers_pkg" "$driver_pkg"
  fi

  if [[ "$HOLD_DRIVER" == "true" ]]; then
    run apt-mark hold "$driver_pkg"
  fi
}

configure_persistenced() {
  local service_file="/etc/systemd/system/nvidia-persistenced-custom.service"

  if [[ "$CONFIGURE_PERSISTENCED" != "true" ]]; then
    log "Skipping nvidia-persistenced setup."
    return
  fi

  if ! command -v nvidia-persistenced >/dev/null 2>&1; then
    warn "nvidia-persistenced is not installed; skipping service setup."
    return
  fi

  log "Writing ${service_file}."
  cat > "$service_file" <<'EOF'
[Unit]
Description=NVIDIA Persistence Daemon (plexvidia)
After=multi-user.target

[Service]
ExecStart=/usr/bin/nvidia-persistenced --user root
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  run systemctl daemon-reload
  run systemctl enable nvidia-persistenced-custom.service
  systemctl restart nvidia-persistenced-custom.service || warn "Could not start nvidia-persistenced-custom.service."
}

set_power_limit() {
  if [[ -z "$POWER_LIMIT" ]]; then
    log "Skipping GPU power limit."
    return
  fi

  if ! [[ "$POWER_LIMIT" =~ ^[0-9]+$ ]]; then
    fail "--power-limit must be an integer watt value."
  fi

  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi -pl "$POWER_LIMIT" || warn "Power limit ${POWER_LIMIT}W is not supported by this GPU/driver."
  else
    log "nvidia-smi not found; cannot set power limit."
  fi
}

configure_plex_preferences() {
  if [[ "$CONFIGURE_PLEX_PREFS" != "true" ]]; then
    log "Skipping Plex Preferences.xml update."
    return
  fi

  if [[ ! -f "$PLEX_PREFS" ]]; then
    warn "Plex preferences file not found: ${PLEX_PREFS}. Start Plex once, then rerun if you want plexvidia to set the transcode directory."
    return
  fi

  local prefs_backup
  prefs_backup="${PLEX_PREFS}.plexvidia.bak.$(date '+%Y%m%d%H%M%S')"
  log "Backing up Plex preferences to ${prefs_backup}."
  cp -a "$PLEX_PREFS" "$prefs_backup"

  local escaped_path
  escaped_path="${TRANSCODE_PATH//&/&amp;}"
  escaped_path="${escaped_path//\"/&quot;}"
  escaped_path="${escaped_path//</&lt;}"
  escaped_path="${escaped_path//>/&gt;}"

  local sed_path
  sed_path="${escaped_path//\\/\\\\}"
  sed_path="${sed_path//&/\\&}"
  sed_path="${sed_path//\//\\/}"

  if grep -q 'TranscoderTempDirectory="' "$PLEX_PREFS"; then
    sed -i -E "0,/TranscoderTempDirectory=\"[^\"]*\"/s//TranscoderTempDirectory=\"${sed_path}\"/" "$PLEX_PREFS"
  elif grep -q '<Preferences' "$PLEX_PREFS"; then
    sed -i -E "0,/<Preferences/s//<Preferences TranscoderTempDirectory=\"${sed_path}\"/" "$PLEX_PREFS"
  else
    fail "Could not find <Preferences> element in Plex Preferences.xml"
  fi

  log "Set Plex TranscoderTempDirectory to ${TRANSCODE_PATH}."
}

restart_plex() {
  if systemctl list-unit-files "$PLEX_SERVICE" >/dev/null 2>&1; then
    systemctl restart "$PLEX_SERVICE" || warn "Failed to restart ${PLEX_SERVICE}."
  else
    warn "Plex service ${PLEX_SERVICE} was not found."
  fi
}

verify_status() {
  log "Verification summary:"
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi || warn "nvidia-smi failed."
  else
    log "nvidia-smi is not available."
  fi

  if systemctl list-unit-files "$PLEX_SERVICE" >/dev/null 2>&1; then
    systemctl --no-pager --full status "$PLEX_SERVICE" || true
  fi

  if [[ -r "$PLEX_LOG" ]]; then
    local log_result
    log_result="$(grep -Ei 'hw|nvenc|cuda|nvidia' "$PLEX_LOG" | tail -n 10 || true)"
    if [[ -n "$log_result" ]]; then
      log "Recent Plex hardware-transcode-related log lines:"
      printf '%s\n' "$log_result"
    else
      log "No recent Plex hardware-transcode log lines found. Start a Plex transcode and rerun with --verify-only."
    fi
  else
    log "Plex log not readable: ${PLEX_LOG}"
  fi
}

main() {
  require_root
  print_banner
  require_command apt-get
  require_command dpkg-query
  require_command systemctl

  if [[ "$PREFLIGHT_ONLY" == "true" ]]; then
    preflight || exit 1
    return
  fi

  detect_platform
  check_secure_boot
  check_gpu_presence

  if [[ "$VERIFY_ONLY" == "true" ]]; then
    verify_status
    return
  fi

  confirm_clean
  [[ "$CLEAN" == "true" ]] && clean_nvidia
  install_driver
  configure_persistenced
  set_power_limit
  configure_plex_preferences
  restart_plex
  verify_status
  log "Plex NVIDIA hardware acceleration setup complete. Log: ${LOG_FILE}"
}

main "$@"
