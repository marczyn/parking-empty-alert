# Examples

Optional configurations for **advanced setups** (multi-camera, LPR, custom integrations).

## ⚠️ When to use examples

**Examples require the [git-clone install path](../docs/INSTALLATION.md#two-installation-paths)**, NOT the pre-built AIO Docker image.

The AIO image (`ghcr.io/marczyn/parking-empty-alert:latest`) is built with a single-camera Reolink config baked in — it doesn't support runtime customization for multi-camera / LPR / multi-spot scenarios.

**Pick example** → `git clone` → copy example configs over base → run `setup.sh`.

If you only need a single-camera setup, **don't use examples** — just use the AIO image directly per [QUICKSTART](../docs/QUICKSTART.md).

---

Each sub-directory is independent — pick what you need.

| Use case | Directory | What it changes |
|---|---|---|
| **Multi-camera** (N separate cameras, N spots) | [`multi-camera/`](multi-camera/README.md) | Replaces `frigate.yml` + `automations.yaml` + `ui-lovelace.yaml` |
| **Multi-spot single-camera** (1 wide-angle, N zones) | [`multi-spot-single-camera/`](multi-spot-single-camera/README.md) | Replaces `frigate.yml` + `automations.yaml` + `ui-lovelace.yaml` + adds `template_sensors.yaml` |
| **License Plate Recognition** | [`lpr/`](lpr/README.md) | Adds `codeproject-ai` service via compose override + LPR Frigate config + plate-aware automations |
| **Non-Reolink cameras** (Hikvision/Dahua/UniFi/Tapo/ONVIF) | [`cameras/`](cameras/README.md) | RTSP URL snippets — replace `ffmpeg.inputs` in `config/frigate.yml` |
| **Telegram notifications** (replace or supplement WhatsApp) | [`telegram/`](telegram/README.md) | Adds `notify.telegram_parking`; no rate limit, supports images |

## Combining examples

Some examples stack:
- **LPR + multi-camera**: copy multi-camera configs, then apply LPR overlay
- **LPR + multi-spot**: copy multi-spot configs, then apply LPR overlay
- **Non-Reolink camera + any of the above**: substitute RTSP URLs only

**LPR + Docker Desktop (macOS/Windows)** requires triple compose override:
```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.macwin.yml \
  -f examples/lpr/docker-compose.lpr.yml \
  up -d
```

## Order of operations

For any example:

1. **Run base `bash scripts/setup.sh` first** — creates `.env`, `secrets.yaml`, Mosquitto passwd
2. Copy example configs over base files
3. **Re-run `bash scripts/setup.sh`** — substitutes `client_id`, `DOCKER_HOST_IP` in new files
4. `docker compose down && docker compose up -d`
5. HA → Settings → Server Controls → Restart

Skipping step 1 means no `.env` → setup.sh prompts you for credentials.
Skipping step 3 means example files retain placeholder `DOCKER_HOST_IP` / collision-prone `client_id`.
