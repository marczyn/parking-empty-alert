# Multi-camera setup

Example configuration for **multiple parking spots in parallel** (e.g., office parking with 3 spots, family parking + garage).

## What changes vs single-camera

| Element | Single (default) | Multi-camera |
|---|---|---|
| `frigate.yml` | 1 camera, 1 zone | N cameras, N zones |
| `automations.yaml` | 1 alert | N alerts + summary |
| RAM | ~600 MB | +400 MB / camera |
| CPU | OK on any host | recommended Coral USB TPU for >3 cameras |
| Network bandwidth | ~1 Mbps | +1 Mbps / camera (sub-stream) |

## How to use

```bash
# 1. Stop the stack
docker compose down

# 2. Copy multi-camera configs over single-camera
cp examples/multi-camera/frigate.yml      config/frigate.yml
cp examples/multi-camera/automations.yaml config/homeassistant/automations.yaml

# 3. Edit camera IPs in config/frigate.yml
#    (3 cameras × 2 RTSP streams = 6 lines to replace)

# 4. Restart
docker compose up -d

# 5. In HA → Settings → Server Controls → Restart
```

## After start

Frigate will auto-discover 3 cameras → HA gets:
- `sensor.parking_a_spot_a_car`
- `sensor.parking_b_spot_b_car`
- `sensor.garage_garage_spot_car`

All 3 automations in `automations.yaml` work immediately — independent alerts.

## Hardware sizing

For N cameras 1080p @ 5 fps:

| N cameras | CPU only | Coral USB | NVIDIA GPU |
|---|---|---|---|
| 1 | ~20% CPU | <5% CPU + ~5W | <5% CPU |
| 2 | ~40% CPU | <10% CPU + ~5W | <5% CPU |
| 3 | ~60% CPU (limit) | ~15% CPU + ~10W | <10% CPU |
| 4-8 | 🔴 not recommended | ~25% CPU + ~15W | ~15% CPU |
| 8+ | no | add 2nd Coral | ✓ OK |
