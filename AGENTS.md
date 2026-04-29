# AGENTS.md

Plexvidia is an admin-facing Bash tool for Plex NVIDIA transcoding on Debian/Ubuntu-style systems, especially Proxmox-managed VMs. Keep operational safety and rollback clarity in sync with code.

## Rules

- Require explicit intent for destructive actions; document clean/purge/removal behavior.
- Do not assume `sudo` inside the script; require root and run commands directly.
- Preserve idempotent normal reruns where practical.
- Back up Plex config before editing it.
- Keep driver branch, GPU power, Plex paths, and service names configurable.
- Log actions clearly; do not hide command failures behind spinners/background jobs.
- Keep remote installer examples compatible with `bash -c "$(curl -fsSL URL)" plexvidia [args]`.

## Docs And Versioning

Update `readme.md` and `CHANGELOG.md` when changing packages, paths, services, defaults, platform support, preflight checks, rollback, logging, remote install, or destructive behavior.

Use SemVer and keep versions aligned in `plexvidia.sh`, `readme.md`, and `CHANGELOG.md`.

## Validate

```bash
bash -n plexvidia.sh
./plexvidia.sh --help
./plexvidia.sh --version
bash -c "$(cat plexvidia.sh)" plexvidia --version
```

For behavior changes, record the tested OS model: Proxmox host, VM, or LXC, plus kernel/header and NVIDIA driver branch.
