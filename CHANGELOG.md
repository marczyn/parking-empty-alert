# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- NAS deployment guides (Synology, UnRAID, QNAP)
- Telegram, Pushover, Gotify notification templates
- Coral USB TPU detailed setup walkthrough
- `make` targets for common operations

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

[Unreleased]: https://github.com/marczyn/parking-empty-alert/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.2.0
[1.0.0]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.0.0
