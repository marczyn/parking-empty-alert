# 🔠 License Plate Recognition (LPR)

Recognize **specific license plates** and customize alerts based on whose car it is.

**Examples:**
- 🟢 "Don't notify me when my own car leaves — I know"
- 🔴 "Notify me URGENTLY when a stranger's car leaves the shared spot (someone may have stolen it)"
- 📊 Log every plate that enters/exits to a database

**Cost:** $0/month (self-hosted via CodeProject AI). No SaaS subscription, no Frigate+ needed.

**Reliability:** ~85-92% read accuracy on Polish plates at 20m, in good light. Lower at night without IR.

---

## How it works

```
[Reolink Camera] ─RTSP─► [Frigate] ──┐
                                     │
                                     ├──► detects "car" + "license_plate"
                                     │
                                     ▼
                            [CodeProject AI]      ◄─── 4th Docker container
                             (ALPR module:        running locally
                              YOLOv8 plate
                              detection + OCR)
                                     │
                                     ▼
                            recognized text e.g.
                            "WX 12345"
                                     │
                                     ▼
                            published to MQTT
                                     │
                                     ▼
                            [Home Assistant] — automation
                            ├── if plate == OWNER_PLATE → suppress alert
                            ├── if plate in BLACKLIST → urgent alert
                            └── log all plates to database
```

CodeProject AI runs locally — no internet required. License plate images never leave your network.

---

## Installation

**Prerequisite:** complete the base setup first (`bash scripts/setup.sh`). This
creates `.env`, `secrets.yaml`, and Mosquitto passwd needed before any LPR work.

### Step 1 — Add CodeProject AI to your stack

⚠️ **Disk space warning:** The CodeProject AI image is **~3 GB** (CPU build)
or **~5 GB** (CUDA build). The ALPR module downloads another **~500 MB** of
models on first install. Ensure 10 GB free before proceeding.

From the main repo directory:

```bash
cp examples/lpr/docker-compose.lpr.yml ./docker-compose.lpr.yml
docker compose -f docker-compose.yml -f docker-compose.lpr.yml up -d
```

This adds a 4th container `codeproject-ai` on port 32168.

⚠️ **Detection model:** Frigate's bundled YOLOv8n was NOT trained on the
`license_plate` class — it sees plates as "noise" inside the car bounding box.
For best LPR results, swap to a model with `license_plate` class
(e.g., YOLOv8n trained on COCO + custom plate dataset). Place in `./model_cache/`
and uncomment the `model:` block in `examples/lpr/frigate.lpr.yml`.

Without a custom model, LPR may detect ~50% of plates in good lighting —
acceptable for owner-verification but not for blacklist surveillance.

Verify:
```bash
curl http://localhost:32168/v1/status/ping
# Should return: {"success":true,"server":"CodeProject.AI Server"}
```

### Step 2 — Enable ALPR module in CodeProject AI

1. Open `http://localhost:32168` in browser
2. Click **Settings** → **Modules**
3. Find **License Plate Reader** → click **Install**
4. Wait ~5 min for model download (~500 MB)
5. After install, the module shows **Running** ✅

### Step 3 — Update Frigate config

Backup current config and apply LPR overlay:

```bash
cp config/frigate.yml config/frigate.yml.bak
cp examples/lpr/frigate.lpr.yml config/frigate.yml
docker compose restart frigate
```

The new config adds:
- `license_plate` to tracked objects
- `genai` section pointing to CodeProject AI for plate OCR

### Step 4 — Add LPR automation in HA

```bash
cat examples/lpr/automations.lpr.yaml >> config/homeassistant/automations.yaml
```

Then add input_text helpers to `config/homeassistant/configuration.yaml`:

```yaml
# Add this block to configuration.yaml (alongside `default_config:`):
input_text:
  owner_plates:
    name: My car plates (comma-separated, uppercase, no spaces)
    initial: "WX12345"      # ← put your own plate(s) here
    max: 100
  blacklist_plates:
    name: Blacklisted plates (comma-separated)
    initial: ""              # ← leave empty or list dangerous plates
    max: 100
```

Then restart HA:
```bash
docker compose restart homeassistant
```

After restart, **edit these from HA UI**: Settings → Devices & Services → Helpers → click "My car plates" → change initial value live (no restart needed).

---

## Configuration

### Suppressing alerts for your own car

After install, your `parking_spot_free_alert` automation has a new condition: it only fires if the **last detected plate ≠ owner_plate**.

In other words:
- 🚗 Your car leaves → plate matches `owner_plate` → **no alert** ✓
- 🚗 Stranger's car leaves → plate ≠ `owner_plate` → alert sent

### Blacklist (urgent alerts)

If a plate in `blacklist_plates` is detected, an additional **🚨 URGENT** WhatsApp is sent immediately (no 2-min delay).

Use case: a known stalker's car, recently reported stolen vehicles, etc.

### Multi-owner setup (family with 2+ cars)

In `secrets.yaml`:
```yaml
owner_plate: "WX12345,WY67890"   # comma-separated
```

The automation suppresses alerts if **any** of these is the detected plate.

---

## Tuning OCR accuracy

If recognition is poor:

### Image quality
- **Camera angle:** plate must be readable, not too oblique. 30-45° from perpendicular is ideal.
- **Distance:** for 1080p camera, plate digits should be at least **20px tall** in frame.
  - 20m distance + 1080p → use camera zoom or move closer
- **Lighting:** night detection needs IR or floodlight aimed at plate area
- **Wet plates / dirt:** wash camera lens monthly

### Frigate config — `examples/lpr/frigate.lpr.yml`

```yaml
objects:
  filters:
    license_plate:
      min_score: 0.5     # lower = more sensitive (more false positives)
      threshold: 0.7
      min_area: 200      # smaller = catch distant plates (less accurate OCR)
```

### CodeProject AI Settings

In CodeProject AI UI → Settings → License Plate Reader → tweak:
- **Confidence threshold:** higher = fewer false positives
- **Country plate format:** if non-Polish, set your country

---

## Hardware considerations

CodeProject AI ALPR module on CPU:

| Hardware | Latency per plate read |
|---|---|
| Intel N100 (no GPU) | ~800 ms |
| Intel i5 + iGPU | ~400 ms |
| NVIDIA GPU (CUDA) | ~80 ms |
| Coral USB TPU | not supported (CPAI is CUDA-only) |
| Raspberry Pi 5 | ~2000 ms (slow but works) |

Latency adds to the end-to-end timing. If your CPU is slow, consider:
1. Lower Frigate detect FPS (already 5 by default)
2. Run CodeProject AI on a separate machine with GPU

---

## Privacy considerations

- 📷 Plate images stay **on your Docker host** — no cloud uploads
- 📝 Plates are logged in HA's database — review `config/homeassistant/home-assistant_v2.db`
- ⚖️ **Legal:** in most EU countries, license plate recognition is GDPR-regulated. Verify local laws before deploying. Recording plates of cars passing your property may require a "data controller" notification.

In Poland (RODO): private use for **your own property** typically OK. Sharing the data or commercial use requires consent / lawful basis.

---

## Troubleshooting

### "No license plates detected"

- Check Frigate UI → Debug → enable Bounding boxes — do you see green boxes around plates?
- If yes but no text → CodeProject AI not reachable. Check `docker compose logs codeproject-ai`
- If no green box → camera too far / angle bad. See "Tuning" above.

### "OCR returns garbage" (random characters)

- Image quality too low — see Tuning section
- Confidence threshold too low — bump up in CodeProject AI Settings

### "My car detected as plate `WX12346` instead of `WX12345`"

- 1-digit OCR errors are common. Use fuzzy match in HA automation:

```yaml
condition:
  - condition: template
    value_template: >
      {% set detected = states('sensor.parking_last_plate') %}
      {% set owner = states('input_text.owner_plate') %}
      {{ detected[:6] == owner[:6] }}    # match first 6 chars only
```

### "Latency too high (alert comes 5 min late)"

- Check CodeProject AI processing time — `docker compose logs codeproject-ai | grep "took"`
- Lower model size in CPAI Settings: Module Settings → ALPR → "Use small model"

---

## Files in this example

```
examples/lpr/
├── README.md                  # this file
├── docker-compose.lpr.yml     # CodeProject AI service definition
├── frigate.lpr.yml            # Frigate config with license_plate tracking + ALPR
└── automations.lpr.yaml       # HA automations: owner suppress + blacklist urgent
```

---

## Alternative LPR providers

CodeProject AI is the default because it's free, self-hosted, and works well. Other options:

| Provider | Cost | Pros | Cons |
|---|---|---|---|
| **CodeProject AI** (default) | Free | Self-hosted, no cloud, ~85-92% accuracy | CPU-only on most hardware |
| **Plate Recognizer** | $5/mo (2500 reads) | High accuracy (~98%), Snap support | SaaS, cloud-dependent |
| **Frigate+** | $50/year | Native integration, no extra container | Subscription, includes other models |
| **OpenALPR** | Free | Self-hosted, mature | Older codebase, lower accuracy |

To switch providers, replace the `genai` block in `frigate.lpr.yml`. See [Frigate ALPR docs](https://docs.frigate.video/configuration/objects/#license-plates).
