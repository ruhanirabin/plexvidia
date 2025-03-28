# 🚀 PLEXVIDIA — The Plex NVIDIA Forge

A bulletproof script for GPU-accelerated Plex transcoding. It configures NVIDIA passthrough, installs drivers, tunes Plex, and verifies everything is running at warp speed.

> **Tool name:** `plexvidia`  
> **Codename:** Plex NVIDIA Forge  
> **By Ruhani Rabin — [ruhanirabin.com](https://www.ruhanirabin.com)**

---

## 🧠 What This Script Does

- Installs NVIDIA driver 535 (if missing)
- Detects and halts if Secure Boot is still enabled
- Offers a "Clean Setup" option to purge existing NVIDIA configs
- Locks the driver version to prevent accidental upgrades
- Creates and starts `nvidia-persistenced` service
- Sets an optional GPU power limit
- Configures Plex to transcode into `/dev/shm` (RAM) for faster performance
- Restarts Plex and checks for GPU transcoding via logs
- Logs everything to `/var/log/plex-nvidia-setup.log`

---

## 📋 Pre-requisites

- Ubuntu 22.04 or 24.04 LTS
- Plex Media Server installed and running
- NVIDIA GPU available on host or passed through (e.g. via Proxmox)
- Internet access
- Secure Boot **must be disabled** in BIOS/OVMF

---

## 🛠 System Preferences

⚠️ Before running this script:
- Ensure your Plex VM/container has GPU passthrough working
- Secure Boot must be off (script will exit otherwise)
- Optional but smart: snapshot your system or VM

---

## 🧪 How to Use It

```bash
chmod +x plexvidia.sh
sudo ./plexvidia.sh
```

You’ll be prompted:
```bash
⚠️  Do you want to perform a CLEAN setup (purge existing NVIDIA drivers)? [y/N]:
```
Answer "y" to start from scratch (removes existing NVIDIA setup).

---

## 🖥 Output
- Logs saved to: `/var/log/plex-nvidia-setup.log`
- Confirmation of GPU transcode via `nvidia-smi`

---

## 🧰 Useful Commands

```bash
watch -n 1 nvidia-smi               # Monitor GPU in real-time
sudo systemctl status plexmediaserver
sudo journalctl -u plexmediaserver
```

---

## 🎨 In the Thoughts
- 🛠 Soon: Ansible version
- 🛠 Soon: Config-based auto-installer

---

## 🤘 Contribute / Fork / Improve
Built for homelabbers, Plex nerds, and GPU-heads. PRs welcome!

---

## ⚠️ Disclaimer
Running in "clean" mode will **purge all NVIDIA-related packages and settings**. Know what you’re doing. Backups are your best friend.

---

**Unleash your GPU. Transcode like a legend. Welcome to the Forge. 🔥**

