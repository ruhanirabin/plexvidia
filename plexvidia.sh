#!/bin/bash

set -e
LOG_FILE="/var/log/plex-nvidia-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ASCII Header Banner
cat <<"EOF"
██████╗ ██╗     ███████╗██╗  ██╗██╗   ██╗██╗██████╗ ██╗ █████╗ 
██╔══██╗██║     ██╔════╝╚██╗██╔╝██║   ██║██║██╔══██╗██║██╔══██╗
██████╔╝██║     █████╗   ╚███╔╝ ██║   ██║██║██║  ██║██║███████║
██╔═══╝ ██║     ██╔══╝   ██╔██╗ ╚██╗ ██╔╝██║██║  ██║██║██╔══██║
██║     ███████╗███████╗██╔╝ ██╗ ╚████╔╝ ██║██████╔╝██║██║  ██║
╚═╝     ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═════╝ ╚═╝╚═╝  ╚═╝
              GPU-Accelerated Plex Transcoding Setup
              aka: Plex NVIDIA Forge • v1.0
          By Ruhani Rabin • https://www.ruhanirabin.com
EOF


# Spinner function
spinner() {
  local pid=$1
  local delay=0.15
  local spinstr='|/-\'
  while ps a | awk '{print $1}' | grep -q "$pid"; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    local spinstr=$temp${spinstr%$temp}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

function log {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🔧 Starting bulletproof NVIDIA/Plex hardware transcode setup..."

# Prompt for clean setup
read -rp "⚠️  Do you want to perform a CLEAN setup (purge existing NVIDIA drivers)? [y/N]: " CLEAN
CLEAN=${CLEAN,,} # tolower

if [[ "$CLEAN" == "y" || "$CLEAN" == "yes" ]]; then
  log "🧹 Performing clean removal of existing NVIDIA drivers..."
  sudo systemctl stop plexmediaserver.service || true & spinner $!
  sudo apt purge -y 'nvidia*' & spinner $!
  sudo apt autoremove --purge -y & spinner $!
  sudo rm -rf /etc/X11/xorg.conf /etc/modprobe.d/nvidia* /lib/modprobe.d/nvidia* /etc/modules-load.d/nvidia* /var/lib/plexmediaserver/Library/Application\ Support/Plex\ Media\ Server/Preferences.xml || true & spinner $!
  sudo rm -rf /etc/systemd/system/nvidia-persistenced-custom.service & spinner $!
  sudo systemctl daemon-reload & spinner $!
  log "✅ Clean removal complete. Proceeding with fresh setup."
fi

# Detect Secure Boot status (only works if mokutil exists)
if command -v mokutil >/dev/null 2>&1; then
  SB_STATE=$(mokutil --sb-state 2>/dev/null | grep -i enabled || true)
  if [[ "$SB_STATE" == *"enabled"* ]]; then
    log "❌ Secure Boot is ENABLED. Please disable Secure Boot to proceed with NVIDIA drivers."
    exit 1
  else
    log "✅ Secure Boot is disabled. Proceeding."
  fi
else
  log "⚠️ mokutil not installed. Skipping Secure Boot check."
fi

# Check if NVIDIA driver 535 is installed
if ! dpkg -l | grep -q nvidia-driver-535; then
  log "📦 Installing NVIDIA driver 535..."
  sudo apt update & spinner $!
  sudo apt install -y nvidia-driver-535 & spinner $!
else
  log "✅ NVIDIA driver 535 already installed."
fi

# Hold driver version
log "🔒 Locking NVIDIA driver version to prevent accidental upgrades."
sudo apt-mark hold nvidia-driver-535 & spinner $!

# Install headers and build tools
log "📦 Ensuring build tools and headers are installed..."
sudo apt install -y dkms build-essential linux-headers-$(uname -r) & spinner $!

# Set up nvidia-persistenced
log "🛠 Setting up NVIDIA persistenced service..."
SERVICE_FILE="/etc/systemd/system/nvidia-persistenced-custom.service"
if [[ ! -f "$SERVICE_FILE" ]]; then
  sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=NVIDIA Persistence Daemon (Manual Startup)
After=multi-user.target

[Service]
ExecStart=/usr/bin/nvidia-persistenced --user root
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable nvidia-persistenced-custom & spinner $!
fi
sudo systemctl start nvidia-persistenced-custom || log "⚠️ Could not start nvidia-persistenced (may already be running)"

# Optional: Power limit
POWER_LIMIT=100
log "⚡ Attempting to set power limit to ${POWER_LIMIT}W..."
sudo nvidia-smi -pl $POWER_LIMIT || log "⚠️ Setting power limit failed (may not be supported on this GPU)"

# Optional: Plex transcode directory
PLEX_PREFS="/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml"
TRANSCODE_PATH="/dev/shm"
if grep -q "<TranscoderTempDirectory>" "$PLEX_PREFS" 2>/dev/null; then
  log "🔁 Updating Plex transcode directory to $TRANSCODE_PATH..."
  sudo sed -i "s#<TranscoderTempDirectory>.*</TranscoderTempDirectory>#<TranscoderTempDirectory>$TRANSCODE_PATH</TranscoderTempDirectory>#g" "$PLEX_PREFS"
else
  log "➕ Adding transcode directory to Plex preferences..."
  sudo sed -i "s#<Preferences #<Preferences TranscoderTempDirectory=\"$TRANSCODE_PATH\" #" "$PLEX_PREFS"
fi

# Restart Plex service
log "🔄 Restarting Plex service..."
sudo systemctl restart plexmediaserver.service || log "⚠️ Failed to restart Plex service"

# Check for hardware transcoding in logs
log "🔍 Scanning Plex logs for hardware transcoding usage..."
LOG_RESULT=$(grep -i "hw" /var/lib/plexmediaserver/Library/Application\ Support/Plex\ Media\ Server/Logs/Plex\ Media\ Server.log | tail -n 10)

if [[ -n "$LOG_RESULT" ]]; then
  log "✅ Hardware transcoding detected in recent logs:"
  echo "$LOG_RESULT"
else
  log "❌ No recent hardware transcode activity found in logs."
fi

log "🎉 Plex NVIDIA hardware acceleration setup complete."
nvidia-smi
