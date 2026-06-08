# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] — 2026-06-08

### Fixed

- **Frigate UI port conflict with Synology DSM** — DSM listens on port 5000/5001 by default. Both AIO images now remap Frigate's nginx listen port from 5000 to **8090** at build time (template override). EXPOSE updated. Users no longer need to manually remap on Synology. ([`Dockerfile.aio-full`](Dockerfile.aio-full), [`Dockerfile.aio-lite`](Dockerfile.aio-lite))
- **Frigate nginx 502 on every request in lite image** — Frigate's nginx sent an auth subrequest to HA on port 5001, which doesn't exist in the lite image. Added `auth: enabled: false` to Frigate config in both images, eliminating the dependency on HA for auth.

---

## [1.0.1] — 2026-06-08

### Fixed

- **s6-overlay service scripts missing `#!/bin/sh`** — `mosquitto` and `homeassistant` longrun `run` scripts were missing the shebang; s6 couldn't execute either service.
- **`FRIGATE_CAMERA_IP` env var not substituted** — RTSP path used a literal placeholder at runtime; camera stream never connected.
- **Home Assistant HTTP config invalid** — `use_x_forwarded_for: true` without `trusted_proxies` caused HA to refuse to start.
- **s6-rc oneshot `init-env` exiting 100** — s6-rc executes oneshot `up` scripts via execlineb (shebang ignored); replaced with `/etc/cont-init.d/10-ha-config.sh` (proper shell script).
- **HA 2024.3 config compatibility** — Removed `default_config:` (pulls in broken `cloud`/`mobile_app`); removed `mqtt: broker:` (removed in HA 2024.1, replaced with pre-baked `.storage/core.config_entries`); added explicit `http: {}`, `frontend: {}`, `websocket_api:`.
- **HA HTTP 500 on every request** — `hass-nabucasa` depends on `acme` which uses `josepy.ComparableX509` (removed in josepy 2+). HA's `forwarded.py` catches only `ImportError` at request time, not `AttributeError`, crashing every HTTP request. Fixed by uninstalling `hass-nabucasa` from the venv.
- **ghcr.io GC deleting amd64 manifest** — ghcr.io auto-deletes untagged package versions. amd64 was always pushed ~30 min before the merge job, giving GC time to remove it. Fixed by pushing each arch with a stable tag (`:amd64`, `:arm64`) to protect the blob; merge step still references by digest.
- **Cleanup workflow destroying manifests** — `cleanup-old-packages.yml` used `delete-only-untagged-versions: false`, deleting the oldest package version after each build (always the amd64 manifest). Changed to `delete-only-untagged-versions: true`.

---

## [1.0.0] — 2026-06-07

Initial release.

### Two all-in-one Docker images (pre-built, multi-arch)

- **`ghcr.io/marczyn/parking-empty-alert:latest`** — FULL: Frigate + Mosquitto + Home Assistant in a single container, orchestrated by s6-overlay. Ports 8090/8123/1883.
- **`ghcr.io/marczyn/parking-empty-alert-lite:latest`** — LITE: Frigate + Mosquitto only (for users with existing HA). Ports 8090/1883.

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
- Auto-cleanup of old package versions (removes untagged only, keeps all tagged)
- Pre-commit hook installation tested in CI
- Multi-arch builds via QEMU + buildx

[1.0.2]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.0.2
[1.0.1]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.0.1
[1.0.0]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.0.0
