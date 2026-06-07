# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-06-07

Initial release.

### Two all-in-one Docker images (pre-built, multi-arch)

- **`ghcr.io/marczyn/parking-empty-alert:latest`** — FULL: Frigate + Mosquitto + Home Assistant in a single container, orchestrated by s6-overlay. Ports 5000/8123/1883.
- **`ghcr.io/marczyn/parking-empty-alert-lite:latest`** — LITE: Frigate + Mosquitto only (for users with existing HA). Ports 5000/1883.

Both images: `linux/amd64` + `linux/arm64`, public, anonymous pull.

### Features

#### Camera support
Universal RTSP — works with any IP camera. Pre-baked config for: Reolink, Hikvision, Dahua, UniFi Protect, TP-Link Tapo, generic ONVIF (Foscam, Wyze, Eufy, Axis).

#### Notifications
- WhatsApp via CallMeBot (free, default, pre-configured)
- Telegram via bot (free, no rate limit)
- Home Assistant Companion App push (iOS critical alerts)

#### Setup variants (via examples/)
- Single camera, single spot (default — pre-baked in AIO images)
- Multi-camera (N separate cameras, N spots)
- Multi-spot single-camera (1 wide-angle, N zones — for parking lots)
- License Plate Recognition (owner detection + blacklist alerts)

#### Platforms
- Linux (native Docker)
- macOS / Windows (Docker Desktop)
- Synology DSM (Container Manager)
- UnRAID (Compose Manager)
- QNAP QTS (Container Station)

#### Operations
- Pre-baked configs — no setup.sh required for AIO images
- Environment variables for runtime customization (CAMERA_IP, RTSP credentials, WhatsApp APIKEY)
- s6-overlay supervises all services in single container
- Health checks for all services
- Pre-commit hook blocks accidental secret leaks (for git clone path)
- `backup.sh` + `restore.sh` scripts (for git clone path)

#### Documentation
- [Quick Start (12 min)](docs/QUICKSTART.md) — pull image → docker run → done
- [Installation Guide](docs/INSTALLATION.md) — detailed step-by-step
- [User Guide](docs/USER_GUIDE.md) — daily ops + advanced + FAQ
- [Synology Surveillance Station coexistence](docs/synology-surveillance-station.md) — 3 ways to integrate with existing SS
- [Multi-VLAN setup](docs/multi-vlan-setup.md) — cameras in IoT VLAN, Frigate in trusted VLAN
- [NAS deployment guides](docs/nas/README.md) — Synology, UnRAID, QNAP
- [Telegram notifications](examples/telegram/README.md)
- [Non-Reolink camera templates](examples/cameras/README.md)

#### CI/CD
- GitHub Actions on self-hosted runners
- Auto-build + push both AIO images on release
- Auto-cleanup of old package versions (keeps 2 latest)
- Pre-commit hook installation tested in CI
- Multi-arch builds via QEMU + buildx

[1.0.0]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.0.0
