# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security

- **CI no longer runs untrusted fork-PR code on the self-hosted runner** — `ci.yml` jobs are gated to pushes and same-repo PRs only (`pull_request.head.repo.full_name == github.repository`), closing an RCE path on the persistent `parking` runner that also builds OVAs / pushes images. ([`ci.yml`](.github/workflows/ci.yml))
- **MQTT broker no longer published to the LAN** — the host port is bound to `127.0.0.1` (was `0.0.0.0`). In-stack clients use the Docker bridge / their configured broker, so nothing breaks, but plaintext MQTT credentials/topics are no longer sniffable or spoofable from the network. ([`docker-compose.yml`](docker-compose.yml))
- **`setup.sh` no longer shell-evaluates `.env`** — replaced `source .env` (a command-injection sink for a camera password like `a$(...)b`) with a literal key=value loader; `.env` values are single-quoted and RTSP credentials reject single quotes. Fixed a `.env` permission regression to `0644` after the HA-admin rewrite (now `0600`). ([`setup.sh`](scripts/setup.sh))
- **`build-vm.yml` packer build hardened** — the version is consumed via an env var instead of `${{ }}`-expansion into the shell, and is allowlist-validated (command-injection on the self-hosted runner). ([`build-vm.yml`](.github/workflows/build-vm.yml))
- **AIO images** — removed baked secret `ENV` defaults (`changeme` / placeholder apikey) in favor of fail-fast on missing runtime secrets; added HA login brute-force protection (`ip_ban_enabled`, `login_attempts_threshold`); escaped `sed` substitution of WhatsApp values. Frigate auth stays disabled by design (trusted-LAN appliance) with explicit warnings. ([`Dockerfile.aio-full`](Dockerfile.aio-full), [`Dockerfile.aio-lite`](Dockerfile.aio-lite))
- **First-boot VM wizard** — replaced `eval` assignment (quote-breakout) with `printf -v`; the secrets file is created mode `0600`; the API key is masked in the summary. ([`parking-wizard.sh`](vm/files/parking-wizard.sh))
- **`restore.sh`** — rejects absolute / `..` traversal members before extracting a (possibly off-host) backup archive. ([`restore.sh`](scripts/restore.sh))
- **Pre-commit secret scanner** — now inspects the staged blob and requires every secret field to still equal its template (was an easily-bypassed any-one-placeholder check). ([`install-git-hooks.sh`](scripts/install-git-hooks.sh))

### Fixed

- **First-boot wizard no longer locks in a broken appliance** — a failed image pull / service start now aborts (and retries next boot) instead of printing "Setup complete" and writing the `configured` sentinel. ([`parking-wizard.sh`](vm/files/parking-wizard.sh))
- **No more false "Frigate recovered" alert on every HA restart** — the recovered watchdog fires only after a real >10-min outage (tracked via an `input_boolean`); both watchdogs also catch the `unknown` state. ([`automations.yaml`](config/homeassistant/automations.yaml), [`configuration.yaml`](config/homeassistant/configuration.yaml))
- **Dashboard no longer reports "Spot OCCUPIED" when detection is offline** — added an unavailable/unknown card and tightened the OCCUPIED condition. ([`ui-lovelace.yaml`](config/homeassistant/ui-lovelace.yaml))
- **A `bus` in the spot now counts as occupied** — the `parking_spot` zone was missing `bus` (tracked but never occupying). ([`frigate.yml`](config/frigate.yml))
- **Package cleanup** only runs after a successful build, and its keep-count default (2) now matches on both the manual and automated paths. ([`cleanup-old-packages.yml`](.github/workflows/cleanup-old-packages.yml))

### Changed

- **VM/OVA pins the app image** to the immutable `:v<version>` tag instead of mutable `:latest`, so each appliance runs exactly the validated image. ([`parking.pkr.hcl`](vm/parking.pkr.hcl))
- **Dependabot** batches action/image bumps into grouped weekly PRs and routes major HA/Frigate jumps to manual review; removed the dead `VERSION_CLEAN` env var. ([`dependabot.yml`](.github/dependabot.yml), [`build-vm.yml`](.github/workflows/build-vm.yml))

---

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
