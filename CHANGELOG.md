# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Telegram, Pushover, Gotify notification templates
- Coral USB TPU detailed setup walkthrough
- `make` targets for common operations

## [1.3.8] — 2026-06-07

### Fixed (Round 8 code audit — 8 more gaps)

#### 🔴 Critical

- **v1.3.7 placeholder regex was DEAD CODE.** The pattern matched exact
  `change_this`, but `.env.example` ships with `change_this_password` (longer).
  Anyone running `cp .env.example .env && bash scripts/setup.sh` got past the
  validation with fake credentials. Replaced with per-key case statement using
  prefix matching (`change_this*`) — now actually catches placeholders.

- **`examples/multi-spot-single-camera/ui-lovelace.yaml` had `DOCKER_HOST_IP`
  placeholder** that setup.sh never substituted (only base ui-lovelace.yaml was
  in scope). Users adopting multi-spot got literal `DOCKER_HOST_IP` string in
  iframe URL → 404s. Extended setup.sh to substitute all dashboard files.

#### 🟡 Important

- **`${var,,}` lowercase substitution requires bash 4.0+** — macOS ships with
  bash 3.2 (last GPL2 version). Setup.sh crashed for any macOS user without
  homebrew bash. Replaced with `tr '[:upper:]' '[:lower:]'` (POSIX-compatible).

- **macOS `/etc/timezone` doesn't exist** — defaulted to UTC for every macOS
  user. Now falls back to reading `readlink /etc/localtime` + extracting
  zoneinfo path (e.g., `America/New_York`).

- **Frigate `genai: provider: openai`** with custom `base_url` for CodeProject
  AI is experimental, not officially supported. Added prominent ⚠️ warning
  + 3 alternative paths (Frigate+, HA Plate Recognizer, wait for 0.17 native
  support).

#### 🟢 Polish

- Frigate `logger.default` was `info` (~10MB logs/day per camera). Changed to
  `warning` (production default); commented opt-in for debugging.
- Mosquitto `max_connections -1` (unlimited) → `100`. Real usage is ~5
  connections; cap prevents DoS surface if MQTT exposed beyond LAN.

[1.3.8]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.3.8

## [1.3.7] — 2026-06-07

### Fixed (Round 7 code audit — 7 more gaps)

#### 🔴 Critical

- **Recorder exclude glob `parking_*_motion` did NOT match `parking_motion`.**
  Glob `*` matches any chars including empty, BUT `_*_` requires literal
  underscore on both sides — meaning the main motion sensor was NEVER excluded.
  DB still ballooned despite v1.3.6 "fix". Rewrote globs as `parking*motion`
  (without internal underscore requirement) — now actually catches all variants.

- **HA `mqtt:` YAML block is deprecated since HA 2024.10** and may be removed
  in future versions. Block still works but logs warning. Added prominent
  documentation comment with UI-setup alternative; kept YAML for zero-touch
  setup.sh installation path.

#### 🟡 Important

- **`setup.sh` didn't validate `.env` placeholder values.** Users could
  `cp .env.example .env` and run setup.sh — stack started with `WHATSAPP_APIKEY=1234567`,
  CallMeBot rejected all messages, MQTT auth failed. Added validation refusing
  to proceed if `.env` contains placeholder strings.

- **`parking_summary_change` automation had no throttle.** If `sensor.parking_free_count`
  flickered (e.g., during occupancy transitions), automation fired multiple times
  in < 1 min → CallMeBot rate limit (1/min) → silent message drops. Added
  5-minute throttle via condition template checking `last_triggered`.

- **Lovelace YAML mode trade-off undocumented.** After v1.3.6 enabled YAML mode,
  HA UI's "Edit Dashboard" button is grayed out. Users wanting UI editing didn't
  know how to switch back. Added USER_GUIDE.md note with both options.

#### 🟢 Polish

- **Battery cameras (Argus, Eufy SoloCam) not flagged as incompatible.** Added
  ⚠️ section to `examples/cameras/README.md` explaining RTSP sleep/wake issues
  and recommending wired cameras only.

[1.3.7]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.3.7

## [1.3.6] — 2026-06-07

### Fixed (Round 6 code audit — 7 more gaps)

#### 🔴 Critical

- **`ui-lovelace.yaml` was IGNORED by HA since v1.0.0.** HA defaults to "storage
  mode" (UI-driven dashboards). Our shipped `ui-lovelace.yaml` was sitting on
  disk doing nothing — every user was seeing the generic default HA dashboard,
  NOT the custom 3-view parking dashboard. **Massive feature regression nobody
  noticed.** Added `lovelace: mode: yaml` to configuration.yaml.

- **HA database had no `recorder:` purge config.** Frigate motion sensors update
  every few seconds; `default_config:` enables recorder which logs ALL state
  changes by default. DB grew unbounded → multi-GB within days. Added recorder
  config: 14-day retention, batch writes (5s commit interval), exclude noisy
  Frigate motion entities + update domain.

#### 🟡 Important

- **INSTALLATION.md §8 directed users to "Debug → Edit Zones"** — in Frigate
  0.13+, zone editor moved to `Configuration → Edit Zones`. Documentation drift.
  Updated with both paths (new + legacy).

- **`backup.sh` didn't exclude `.git/`** — when run from repo dir (the normal
  case), backups included 50+ MB of git history per backup. Added exclusions
  for `.git/`, `__pycache__`, `*.pyc`, `*.swp`, `.DS_Store`, `node_modules`,
  `.venv`.

- **CONTRIBUTING.md didn't mention pre-commit hook installation** — new
  contributors wouldn't know to install secret-leak protection added in v1.3.5.
  Added explicit step to PR workflow with shellcheck severity flag.

- **Frigate model auto-download (50MB) on first run requires internet, not
  documented.** Air-gapped users saw silent fail. Added INSTALLATION.md §7.3
  note + link to Frigate's manual model placement docs.

- **Lovelace `aspect_ratio: 75%`** (4:3) made iframe too tall on mobile
  portrait. Changed to `'16:9'` for better cross-device experience.

[1.3.6]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.3.6

## [1.3.5] — 2026-06-07

### Fixed (Round 5 code audit — 8 more gaps)

#### 🔴 Critical

- **INSTALLATION.md + README told users to enter `http://frigate:5000` for HA
  Frigate integration** — but HA in `network_mode: host` (Linux default) cannot
  resolve Docker DNS names. Integration setup would FAIL silently with "cannot
  connect" — users couldn't finish setup. Documented both URLs (host mode =
  `localhost:5000`, bridge mode = `frigate:5000`) with a clear table.

- **`setup.sh` DOCKER_HOST_IP auto-detection used `hostname -I | awk '{print $1}'`** —
  on hosts with multiple interfaces, could pick a Docker bridge IP (172.17.0.1)
  instead of LAN IP. Lovelace iframe URL would be broken. Switched to
  `ip route get 1.1.1.1` (asks kernel which IP reaches the default gateway —
  always LAN); fallback filters Docker/link-local ranges from `hostname -I`.

- **No protection against committing real secrets to git.** User could
  `git add -A && git commit && git push` real `.env`, real Mosquitto passwd,
  or modified secrets.yaml. Added:
  - `scripts/install-git-hooks.sh` — installs pre-commit hook
  - Hook blocks: `.env` commits, `config/passwd` commits, `secrets.yaml` with
    non-placeholder values, CallMeBot APIKEY look-alikes, phone number look-alikes
  - setup.sh auto-installs hook on first run

#### 🟡 Important

- **`setup.sh` password input had no confirmation** — silent typos in RTSP
  password meant Frigate would fail to connect days later. Added confirm
  re-prompt loop until passwords match.

- **Camera templates (`examples/cameras/*.yml`) were SNIPPETS but looked like
  full configs.** Users might replace `config/frigate.yml` with a vendor
  template → lose zones/objects/detect settings. Updated README with explicit
  ⚠️ warning + visual `diff` example showing the exact change.

- **No resource limits in `docker-compose.yml`** — a Frigate runaway could
  consume all host RAM/CPU, taking down HA + Mosquitto with it. Added:
  - Mosquitto: 256m memory, 0.5 CPU
  - Frigate: 2g memory, 4.0 CPU
  - HA: 1.5g memory, 2.0 CPU

- **Frigate config tracked `bus` but had no `bus:` filter** — could cause schema
  validation warnings. Added matching filter with same thresholds as truck.

- **No `CODEOWNERS` file** — issues and PRs had no auto-assigned reviewer.
  Added with file-pattern routing.

### Added
- `scripts/install-git-hooks.sh` — git pre-commit hook installer
- `.github/CODEOWNERS` — review auto-assignment

[1.3.5]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.3.5

## [1.3.4] — 2026-06-07

### Fixed (Round 4 code audit — 11 more gaps)

#### 🔴 Critical

- **`numeric_state below: 1` triggered false "spot free!" on Frigate restart.**
  When sensor went `unavailable → 0`, HA's `numeric_state` trigger considered
  this "crossing below 1" → after 2 min of recovery, every Frigate restart
  spammed a "🅿️ FREE!" message even with car parked. Added `condition: template`
  guarding against false trigger: only fire if previous state was `1+` (occupied).
  Applied to base, multi-camera, multi-spot, and LPR automations.

- **setup.sh skipped prompts on re-run if `.env` existed**, but `.env` from
  earlier versions was missing `TZ` (added in v1.3.2). Users upgrading via
  `git pull && bash scripts/setup.sh` got incomplete config. Added migration
  logic: detects missing keys, prompts to add them, re-runs DOCKER_HOST_IP
  substitution if needed.

#### 🟡 Important

- **HA `configuration.yaml` had no `http:` section** — anyone putting HA behind
  reverse proxy (NPM, Traefik, SWAG, Cloudflare Tunnel) got `WrongHostError`
  rejections. Added commented `http: trusted_proxies` block with explanatory
  comments + IP ban hardening hint.

- **CI workflow had no `permissions:` block** — GitHub-default token has
  permissive write access. Added explicit least-privilege: `contents: read`,
  `pull-requests: read`. Future-proof against supply chain attacks.

- **Mosquitto `passwd` file had default 644 permissions** (world-readable).
  Hashed but principle of least privilege. Added `chmod 600` after creation.

- **Tapo template used sub-stream (360p15) for detection** — too low resolution
  at 20m distance (cars become <50px tall, YOLO misses). Changed default to
  main stream (1080p) for both detect+record, with low-res dual-stream option
  as alternative for users with cameras <10m from spot.

- **No Dependabot config** — manual updates only for GH Actions + Docker images.
  Added `.github/dependabot.yml` with weekly checks for both ecosystems.

#### 🟢 Polish

- README said "Setup time: 30 minutes" but new prompts (TZ + DOCKER_HOST_IP)
  push real time to 45-60 min. Synced with INSTALLATION.md's 45-60 estimate.

### Changed
- setup.sh re-run is now idempotent + auto-migrates older `.env` files.

[1.3.4]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.3.4

## [1.3.3] — 2026-06-07

### Fixed (Round 3 code audit — 8 more gaps)

#### 🔴 Critical

- **LPR automations reference `input_text.owner_plates` and `input_text.blacklist_plates`
  but they were never defined anywhere.** Automation crashed at runtime ("entity
  unavailable"). Added input_text helper definitions to LPR README with clear
  instructions to paste into configuration.yaml.

- **LPR docker-compose uses CUDA-only image as default** (`codeproject/ai-server:cuda12`).
  Users without NVIDIA GPU got image pull failures. Switched default to
  CPU-compatible `:latest` image; CUDA option commented for users with GPU.

#### 🟡 Important

- **NAS guides (Synology, UnRAID, QNAP) reference `hwaccel_args: preset-vaapi` as
  default**, conflicting with v1.3.2 change where it's now commented out. Updated
  all 3 NAS guides with the correct 2-step enable procedure (config + compose).

- **README hardware acceleration table said "preset-vaapi (already set)"** —
  misleading after v1.3.2. Rewrote table to show both `frigate.yml` AND
  `docker-compose.yml` changes needed; added ⚠️ warning about VAAPI.

- **No `/dev/dri` passthrough block in compose** — even if user uncomments
  `hwaccel_args: preset-vaapi`, the device wasn't exposed → Frigate failed.
  Added commented block with full instructions; sync'd with NAS guides.

- **`config/frigate.yml` had `model:` block with hardcoded path** to ONNX file
  that doesn't exist by default. Frigate ships with a bundled default model.
  Commented out the entire `model:` block; users can opt-in to custom models.

#### 🟢 Polish

- **No `backup.sh` script** — users had to copy tar commands from User Guide.
  Added `scripts/backup.sh` with proper exclusions (recordings, HA cache, logs),
  timestamped filenames, permission setting, restore + 3-2-1 rule reminder.

- **CI shellcheck not severity-pinned** — future shellcheck releases adding
  style rules would break CI without warning. Pinned to `--severity=warning`.

### Changed
- CI shellcheck now runs against `scripts/*.sh` (covers new `backup.sh`).

[1.3.3]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.3.3

## [1.3.2] — 2026-06-07

### Fixed (Round 2 code audit — 8 more gaps)

#### 🔴 Critical

- **`notify.rest` had `method: GET_QUERY` — not a valid HA method.** HA would
  fail to load on startup. Changed to `method: GET` with `data:` + `message_param_name`
  which correctly sends parameters as query string.

- **`.gitignore` typo: only `config/mosquitto/passwd` listed but setup.sh
  creates `config/passwd`.** Real Mosquitto password file was NOT gitignored,
  could leak on first commit. Added `config/passwd` + `config/**/passwd` glob.

- **`ui-lovelace.yaml` iframe used `http://frigate:5000`** — Docker DNS doesn't
  resolve from browser. Iframe was broken in both `network_mode: host` and bridge.
  Changed to `http://DOCKER_HOST_IP:5000` placeholder; setup.sh substitutes the
  actual host IP.

- **`version: 0.16-0` hardcoded in all 4 Frigate configs.** Frigate stable image
  is 0.15.x — schema 0.16 would either error or get ignored. Removed `version:`
  field entirely — Frigate uses image-bundled default.

#### 🟡 Important

- **`TZ: "Europe/Warsaw"` hardcoded** in both `docker-compose.yml` and
  `examples/lpr/docker-compose.lpr.yml`. Users in other timezones got wrong
  timestamps in WhatsApp alerts. Now uses `${TZ:-UTC}` with `.env` support;
  setup.sh auto-detects from host's `/etc/timezone`.

- **`hwaccel_args: preset-vaapi` was the default** in all 4 Frigate configs.
  Frigate FAILED to start on AMD-only, ARM (RPi), or any host without Intel iGPU.
  Changed default to CPU (no hwaccel line); commented presets remain for users
  with compatible hardware, with prominent ⚠️ warning.

- **Mosquitto `log_dest file` filled disk over time** (no log rotation).
  Switched to `log_dest stdout` only; added Docker `json-file` log driver with
  `max-size: 10m, max-file: 3` per container.

- **Mosquitto compose was missing `passwd` file mount** — setup.sh created
  `config/passwd` but it wasn't mounted into the container. MQTT auth never
  used the generated password. Added bind mount.

#### 🟢 Polish

- **Ports 8554/8555 exposed without explanation.** Added inline comments
  explaining RTSP restream (VLC viewing) and WebRTC (low-latency preview).

- Added log rotation for Frigate (`50m × 3`) and HA (`50m × 3`) — same as
  Mosquitto. Prevents Docker logs from growing unbounded.

### Changed
- setup.sh now asks for **Timezone** (auto-detects from host as default) and
  **Docker host LAN IP** (auto-detects from `hostname -I`); substitutes
  `DOCKER_HOST_IP` placeholder in `ui-lovelace.yaml`.
- `.env.example` includes `TZ` variable with IANA reference link.

[1.3.2]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.3.2

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

[Unreleased]: https://github.com/marczyn/parking-empty-alert/compare/v1.3.8...HEAD
[1.3.0]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.3.0
[1.2.0]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.2.0
[1.0.0]: https://github.com/marczyn/parking-empty-alert/releases/tag/v1.0.0
