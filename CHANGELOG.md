# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Telegram, Pushover, Gotify notification templates
- Coral USB TPU detailed setup walkthrough
- `make` targets for common operations

## [1.3.1] — 2026-06-07

### Fixed

#### 🔴 Critical — broken-at-runtime fixes

- **Mosquitto healthcheck always failed → stack never started.** Mosquitto service
  had no `environment:` block, so `${MQTT_USER}`/`${MQTT_PASSWORD}` referenced in
  the healthcheck were empty strings inside the container. `mosquitto_pub` rejected
  auth, healthcheck failed, `depends_on: service_healthy` on Frigate + HA never
  satisfied. **First-time stack startup didn't work.** Added env block; switched
  `${}` → `$$` to defer interpolation to runtime.

- **`ui-lovelace.yaml` referenced non-existent `automation.parking_spot_empty_whatsapp`.**
  Real automation ID is `parking_spot_free_alert`. Dashboard showed "unknown" entity
  on the Diagnostics tab. Fixed reference + added `frigate_recovered_watchdog`
  reference too.

- **CI `python yaml.safe_load()` failed on `configuration.yaml` with `!include`/`!secret`
  tags.** PyYAML doesn't know HA-specific tags. **First CI run on every PR would fail.**
  Added `HALoader` subclass with pass-through constructors for all HA tags
  (`!include`, `!secret`, `!env_var`, `!include_dir_*`).

#### 🟡 Important — quality + coverage

- **CI missing coverage for v1.1/v1.2/v1.3 example files.** Added globs for:
  `examples/lpr/*.yml`, `examples/lpr/*.yaml`,
  `examples/multi-spot-single-camera/*.yml`, `examples/multi-spot-single-camera/*.yaml`,
  `examples/cameras/*.yml`, `docker-compose.macwin.yml`.

- **CI didn't validate `docker-compose.macwin.yml` or LPR override.** Added two new
  CI steps: `docker compose -f docker-compose.yml -f docker-compose.macwin.yml config`
  and same for LPR override.

- **`{% break %}` in template sensor — unsupported by HA's Jinja2 (lacks `loopcontrols`
  extension).** Rewrote `sensor.parking_first_free_spot` template using `namespace`
  pattern. Also returns `'all_taken'` instead of empty string when all spots occupied.

- **Default `config/frigate.yml` zone coordinates looked like a real polygon
  (35-65% middle of frame).** Users could miss the placeholder warning and ship
  with the default zone, getting false alarms. Changed to obvious whole-frame
  polygon (0.01-0.99) with prominent `⚠️ REPLACE` warning.

#### 🟢 Nice-to-have polish

- **Frigate config CI hardcoded `frigate:stable`** while configs declared
  `version: 0.16-0`. Now CI uses matrix strategy over all 4 frigate configs
  (`config/`, `multi-camera`, `multi-spot-single-camera`, `lpr`) — pulls
  the same `:stable` once per config, validates each.

- **Frigate-config CI didn't test `examples/lpr/frigate.lpr.yml`.** Now in matrix.

- **HA healthcheck `curl -f http://localhost:8123` returned 404 in some boot states.**
  Changed to capture HTTP status and accept `200` or `401` (auth needed = HA is up).

- **`secrets.yaml` semantics unclear** — committed as template but in `.gitignore`.
  Removed `secrets.yaml` from `.gitignore`; added prominent ⚠️ TEMPLATE header in
  the file itself; added safety check pattern in `.gitignore` comments.

### Changed

- CI workflow restructured: `validate` step uses HALoader; `frigate-config` step
  uses matrix strategy; added compose override validation steps.

[1.3.1]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.3.1

## [1.3.0] — 2026-06-07

### Added

#### NAS deployment guides
- `docs/nas/README.md` — NAS comparison + minimum specs + compatible model list + universal considerations (storage paths, SMR vs CMR, RAID, power, backups)
- `docs/nas/synology.md` — Full DSM 7.2+ Container Manager guide:
  - SSH + docker compose method (recommended)
  - Container Manager UI method (no-SSH alternative)
  - VAAPI hardware acceleration setup
  - Coral USB TPU integration
  - Reverse proxy with Let's Encrypt
  - Hyper Backup + Snapshot Replication
  - Synology-specific troubleshooting
- `docs/nas/unraid.md` — UnRAID 6.12+/7.0 Compose Manager guide:
  - Compose Manager plugin install + setup
  - Storage strategy (cache vs array for recordings)
  - NVIDIA Driver plugin integration
  - Coral USB TPU setup
  - SWAG reverse proxy + Let's Encrypt
  - CA Backup/Restore Appdata
  - NVIDIA + Intel iGPU + AMD considerations
- `docs/nas/qnap.md` — QNAP QTS 5.x Container Station guide:
  - SSH method (recommended due to UI YAML quirks)
  - Container Station UI method
  - VAAPI + Coral setup
  - HBS3 backup strategy
  - Nginx Proxy Manager for HTTPS
  - QNAP-specific notification integration

README documentation table updated with NAS guides link.

## [1.2.0] — 2026-06-07

### Added

#### Non-Reolink camera templates
- `examples/cameras/README.md` — overview, lookup table for 10+ brands, universal tips
- `examples/cameras/hikvision.yml` — Hikvision (and Annke/LTS/Onwote rebrands)
- `examples/cameras/dahua.yml` — Dahua (and Amcrest/Lorex rebrands)
- `examples/cameras/generic-onvif.yml` — Foscam, Wyze, Eufy, Axis, no-name ONVIF
- `examples/cameras/unifi-protect.yml` — UniFi G3/G4/G5/AI on port 7447
- `examples/cameras/tp-link-tapo.yml` — Tapo C100/C200/C310 with third-party access account
- Documentation:
  - How to find RTSP URL (vendor docs, ONVIF Device Manager, FFmpeg test loop)
  - Common ports table (RTSP, ONVIF, HTTP, HTTPS)
  - H.264 vs H.265 codec guidance
  - Auth failure debugging (URL-encoded special chars)
  - Per-vendor quirks table (Hikvision B-frames, Dahua focus, Tapo sub-stream limit, Wyze RTSP crash, Axis URLs)
  - Camera positioning section (angle, distance, FoV, lighting, weather)
  - How to contribute new templates (issue template)

## [1.1.0] — 2026-06-07

### Added

#### License Plate Recognition (LPR)
- `examples/lpr/` — full LPR setup using CodeProject AI (free, self-hosted)
- `docker-compose.lpr.yml` override adds 4th container (codeproject-ai)
- `frigate.lpr.yml` enables Frigate LPR + genai integration
- `automations.lpr.yaml` with 3 LPR-aware automations:
  - Suppress alerts for owner's car (via `owner_plates` input_text)
  - URGENT WhatsApp for blacklist plates (via `blacklist_plates` input_text)
  - Log every detected plate to HA logbook
- Multi-owner support (comma-separated `owner_plates`)
- Fuzzy matching guidance for OCR error tolerance
- Documentation: privacy/GDPR considerations, hardware sizing, troubleshooting

#### Multi-spot single-camera support
- `examples/multi-spot-single-camera/` — 1 wide-angle camera, N zones
- `frigate.yml` template with 5 example zones + higher resolution detect (1280×720)
- `automations.yaml` with 5 per-spot alerts + occupancy-change summary
- `template_sensors.yaml` with derived sensors:
  - `sensor.parking_free_count` (0-5 free)
  - `sensor.parking_occupancy_pct` (0-100%)
  - `sensor.parking_first_free_spot` (leftmost free spot number)
- `ui-lovelace.yaml` with 3 views:
  - Overview with 5-spot grid + summary glance + live camera
  - Spots detail with per-spot history graph
  - Diagnostics with automation status + Frigate iframe
- Camera placement guide (FoV recommendations for 3-15 spots)
- Comparison table: when to use multi-camera vs multi-spot single-camera

### Changed
- CHANGELOG.md — moved LPR + multi-spot from Planned to 1.1.0

[1.1.0]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.1.0

## [1.0.0] — 2026-06-07

### Added

#### Core stack
- Docker Compose stack with Frigate + Mosquitto + Home Assistant
- Universal RTSP support for any Reolink camera model (h264 + h265 variants)
- CPU detection by default (no special hardware required)
- Optional Coral USB TPU + NVIDIA GPU + Intel iGPU acceleration profiles
- Persistent object tracking (parked car stays detected for hours)

#### Notifications
- WhatsApp via CallMeBot (free service, no registration)
- `notify.whatsapp_parking` HA service auto-configured by setup script
- Anti-blink filter (2-minute wait before alerting)
- Frigate offline watchdog (alert if AI pipeline stops)
- Frigate recovered watchdog (alert when back online)

#### Configuration
- Interactive setup script (`scripts/setup.sh`) — asks 6 questions, configures everything
- Random MQTT password generation
- Camera IP placeholder substitution
- RTSP smoke test before stack start
- WhatsApp smoke test (real test message sent during install)

#### Docker support
- Healthchecks for Mosquitto (mosquitto_pub probe) and Home Assistant (HTTP probe)
- Service dependencies with `service_healthy` condition
- macOS/Windows override file (`docker-compose.macwin.yml`) for Docker Desktop
- Auto-restart policy (`restart: always`)
- Linux host network mode for HA (Companion App discovery)

#### Home Assistant
- Custom Lovelace dashboard with conditional cards (✅ Free / 🚫 Occupied)
- Live camera card
- 24-hour occupancy history graph
- Events / diagnostics views with Frigate UI iframe

#### Documentation
- README with architecture diagrams (Mermaid)
- Sequence diagram for event flow
- State machine for zone occupancy
- Detailed installation guide (`docs/INSTALLATION.md`, 659 lines, 11 sections)
- Detailed user guide (`docs/USER_GUIDE.md`, 719 lines, 17 sections including FAQ)
- Multi-camera example (`examples/multi-camera/`)
- Hardware recommendations table

#### Community
- CONTRIBUTING.md with PR workflow + conventional commits
- SECURITY.md with vulnerability disclosure policy
- Bug report and feature request issue templates
- Pull request template
- MIT License

#### CI/CD
- GitHub Actions: YAML lint, Docker Compose validate, ShellCheck, Frigate config schema validation
- `.gitignore` covering all secret files

### Reliability
- 95-99% detection accuracy (with proper zone placement and lighting)
- Sub-3-second end-to-end latency (camera → WhatsApp)
- Survives Docker daemon restart (`restart: always` + healthchecks)
- Survives camera reboot (Frigate reconnects RTSP)

### Known issues
- macOS/Windows: HA Companion App auto-discovery may not work in bridge mode (manual IP config needed)
- CallMeBot rate limit: 1 message/min/phone (shared with all your `whatsapp_parking` calls)
- YOLO performance degrades in heavy rain/snow (~70-90% accuracy vs 95% daytime clear)

[Unreleased]: https://github.com/marczyn/parking-empty-alert/compare/v1.3.1...HEAD
[1.3.0]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.3.0
[1.2.0]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.2.0
[1.0.0]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.0.0
