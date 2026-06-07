# 🅿️🅿️🅿️ Multi-spot single-camera

Monitor **N parking spots with ONE wide-angle camera**. Each spot has its own zone, its own sensor, its own alert.

**Use cases:**
- Office parking with 5+ spots visible from one camera
- Apartment building shared parking area
- Public street monitoring (5-10 spots in a row)

This is **different from** multi-camera setup (`examples/multi-camera/`):
- **Multi-spot single-camera (this):** 1 camera, N zones, 1 RTSP stream → CPU/RAM saved
- **Multi-camera:** N cameras, N zones, N RTSP streams → use when spots are too far apart for one camera

## Camera placement

For multi-spot monitoring you need a **wide-angle camera**:

| Spots | Recommended camera | FoV needed |
|---|---|---|
| 3-4 spots in a row | Reolink RLC-810A (FoV 87°) | OK with standard lens |
| 5-7 spots | Reolink RLC-820A or Duo 2 (180° dual-lens) | wide-angle required |
| 8-15 spots | Reolink TrackMix (PTZ with auto-tracking) | use PTZ presets |
| 15+ spots | Multiple cameras (use `examples/multi-camera/`) | physics limit |

**Mounting tips:**
- High angle (3-4m) looking down → minimizes occlusion between cars
- Center the camera between leftmost and rightmost spot
- Avoid extreme angles — far-left and far-right spots will have distorted detection
- Distance: 10-25m optimal. >30m → car may be too small for YOLO

## Architecture

```
[Wide-angle Reolink] ─RTSP─► [Frigate]
                              │
                              ├─ Zone "spot_1" → sensor.parking_spot_1_car
                              ├─ Zone "spot_2" → sensor.parking_spot_2_car
                              ├─ Zone "spot_3" → sensor.parking_spot_3_car
                              ├─ Zone "spot_4" → sensor.parking_spot_4_car
                              └─ Zone "spot_5" → sensor.parking_spot_5_car
                                                          │
                                                          ▼
                              [HA] ──► 5 automations + 1 summary sensor
                                                          │
                                                          ▼
                                                    WhatsApp:
                                                    "🅿️ Spot 3 free!"
                                                    "📊 3 of 5 spots free"
```

## Installation

**Prerequisite:** complete the base setup first (`bash scripts/setup.sh`). This
creates `.env`, `secrets.yaml`, and Mosquitto passwd needed by ALL camera setups.

### Step 1 — Apply multi-spot Frigate config

```bash
cp examples/multi-spot-single-camera/frigate.yml config/frigate.yml
bash scripts/setup.sh   # re-runs substitutions on new config
docker compose restart frigate
```

This config defines **5 zones** on a single camera. You'll need to draw each zone in Frigate UI (see below).

### Step 2 — Apply multi-spot HA configs

```bash
cp examples/multi-spot-single-camera/automations.yaml config/homeassistant/automations.yaml
cp examples/multi-spot-single-camera/template_sensors.yaml config/homeassistant/template_sensors.yaml
cp examples/multi-spot-single-camera/ui-lovelace.yaml config/homeassistant/ui-lovelace.yaml
```

Add to `configuration.yaml`:
```yaml
sensor: !include template_sensors.yaml
```

Restart HA:
```bash
docker compose restart homeassistant
```

### Step 3 — Draw the 5 zones in Frigate UI

This is the **most important** step.

1. Open Frigate UI: `http://localhost:5000`
2. Click camera `parking_lot`
3. Click **Debug**
4. Click ⚙ **Settings → Edit Zones**
5. **Add zone `spot_1`** — draw polygon around leftmost spot, save
6. **Add zone `spot_2`** — second spot
7. Repeat for `spot_3`, `spot_4`, `spot_5`
8. Each "Save" gives you a coordinate string
9. Copy each into `config/frigate.yml`:

```yaml
zones:
  spot_1:
    coordinates: 0.05,0.40,0.20,0.40,0.20,0.85,0.05,0.85   # paste leftmost
  spot_2:
    coordinates: 0.20,0.40,0.35,0.40,0.35,0.85,0.20,0.85   # paste 2nd
  spot_3:
    coordinates: 0.35,0.40,0.50,0.40,0.50,0.85,0.35,0.85   # paste middle
  spot_4:
    coordinates: 0.50,0.40,0.65,0.40,0.65,0.85,0.50,0.85   # paste 4th
  spot_5:
    coordinates: 0.65,0.40,0.80,0.40,0.80,0.85,0.65,0.85   # paste rightmost
```

10. Restart Frigate: `docker compose restart frigate`
11. Verify in Frigate Debug view: you should see **5 green polygons**

## What you get in HA

### Entities

Frigate auto-creates per zone:

| Entity per spot | What |
|---|---|
| `sensor.parking_lot_spot_N_car` | Car count in zone N (0 or 1) |
| `binary_sensor.parking_lot_spot_N_car_occupied` | Binary occupied/free |
| `image.parking_lot_spot_N` | Latest snapshot of that zone |

Plus from `template_sensors.yaml`:

| Template sensor | What |
|---|---|
| `sensor.parking_free_count` | Number of free spots (0-5) |
| `sensor.parking_occupancy_pct` | Occupancy percentage |
| `sensor.parking_first_free_spot` | Number of leftmost free spot (helpful for navigation) |

### Automations (per spot)

- `parking_spot_N_free` × 5 — sends WhatsApp when spot N becomes empty
- `parking_summary_change` — sends summary when occupancy changes ("3 of 5 free now")

### Dashboard

Beautiful grid showing all 5 spots at once:

```
┌────────────────────────────────────────────────────────────┐
│                    🅿️ Parking Status                       │
│                                                            │
│           3 of 5 spots FREE   (60% occupied)               │
│                                                            │
│   ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐         │
│   │  1   │  │  2   │  │  3   │  │  4   │  │  5   │         │
│   │  🚗  │  │  ✅  │  │  🚗  │  │  ✅  │  │  ✅  │         │
│   │ taken│  │ FREE │  │ taken│  │ FREE │  │ FREE │         │
│   └──────┘  └──────┘  └──────┘  └──────┘  └──────┘         │
│                                                            │
│   [📷 Live camera view]                                    │
└────────────────────────────────────────────────────────────┘
```

## Customization

### Change number of spots (3, 7, 10, 15)

Edit `frigate.yml` — add/remove `spot_N:` blocks in `zones:`. Then edit `automations.yaml` and `template_sensors.yaml` to match.

### Change "summary" threshold

Currently: alert fires when occupancy changes by ≥1 spot. To alert only on big changes:

```yaml
- id: parking_summary_change
  trigger:
    - platform: numeric_state
      entity_id: sensor.parking_free_count
      above: 3   # alert only when ≥3 spots free
      for: {minutes: 2}
```

### Disable individual spot alerts (only summary)

Comment out `parking_spot_N_free` automations, keep `parking_summary_change`.

### Per-spot priority

If spot 1 is "premium" (closest to door), set its `for:` to `30 seconds` instead of `2 minutes`:

```yaml
- id: parking_spot_1_free
  trigger:
    - platform: numeric_state
      entity_id: sensor.parking_lot_spot_1_car
      below: 1
      for:
        seconds: 30   # premium spot — faster alert
```

## Hardware sizing

For N zones on **one** camera (1080p @ 5fps):

| N zones | CPU only | Coral USB | NVIDIA GPU |
|---|---|---|---|
| 1-5 | ~25% CPU | <5% CPU + ~5W | <5% CPU |
| 6-10 | ~30% CPU | <10% CPU + ~5W | <5% CPU |
| 11-15 | ~35% CPU | <15% CPU + ~10W | <5% CPU |

Zones are very cheap — once Frigate detects a car, checking if it's in zone X is O(1). Compute scales with cameras, NOT zones. Recommendation: try CPU first.

## Comparison: which to use

| Question | Multi-camera | Multi-spot single-camera |
|---|---|---|
| Spots are >30m apart | ✅ use this | ❌ camera can't see all |
| Spots are <20m apart, same area | acceptable | ✅ better (1 cam, less hardware) |
| You already have N cameras installed | use them | requires re-positioning |
| Cost-conscious | $$$ (N cameras) | $ (1 wide-angle camera) |
| Premium picture quality per spot | each spot in 1080p | each spot ~360px wide |
| LPR works well | ✅ closer to plates | ⚠️ plate may be tiny |

If you need LPR + multi-spot, prefer **multi-camera** (LPR needs ≥20px tall plate digits, which requires zoom or proximity).

## Files in this example

```
examples/multi-spot-single-camera/
├── README.md                  # this file
├── frigate.yml                # 1 camera, 5 zones config
├── automations.yaml           # 5 alerts + summary
├── template_sensors.yaml      # free_count + occupancy_pct + first_free_spot
└── ui-lovelace.yaml           # grid dashboard
```
