# 🎥 Coexisting with Synology Surveillance Station

Already running your cameras through **Synology Surveillance Station**? This
guide covers 3 ways to add parking detection without disrupting your existing
NVR setup.

## TL;DR

| Approach | When to use | Setup complexity |
|---|---|---|
| **[A) Co-existence](#option-a--co-existence-recommended)** | Camera supports multiple RTSP clients (most do) | Easy |
| **[B) Surveillance Station RTSP restream](#option-b--surveillance-station-rtsp-restream)** | Camera limits RTSP clients OR you want single connection point | Medium |
| **[C) Use SS AI instead of Frigate](#option-c--use-surveillance-station-ai-instead)** | Already have SS Device Licenses and don't want extra containers | Medium |

**Recommendation:** Start with **Option A**. Switch to B or C only if A doesn't work.

---

## Option A — Co-existence (recommended)

Most modern IP cameras (Reolink, Hikvision, Dahua, UniFi Protect, TP-Link Tapo)
support **2-4 simultaneous RTSP connections**. Both Surveillance Station AND
Frigate can pull from the same camera in parallel — zero conflict.

### Architecture

```
                                   ┌─→ RTSP main (1080p) → Synology Surveillance Station (recording, viewing)
[Reolink Camera] ────────RTSP─────┤
                                   └─→ RTSP sub  (640×360) → Frigate (zone detection)
                                                                  │
                                                                  ▼
                                                              [HA + WhatsApp]
```

- **Surveillance Station:** uses **main stream** (high quality for recording, NVR features)
- **Frigate:** uses **sub stream** (low resolution, just enough for AI detection)
- Cameras serve both clients simultaneously

### Configuration

This is the **default** in this project. `config/frigate.yml` already uses sub-stream
for detection.

If you want Frigate to skip recording (since Surveillance Station already records),
edit `config/frigate.yml`:

```yaml
cameras:
  parking:
    ffmpeg:
      inputs:
        - path: rtsp://...@CAMERA_IP:554/h264Preview_01_sub
          roles: [detect]           # AI detection only
        # Comment out OR remove the main stream — Surveillance Station handles recording
        # - path: rtsp://...@CAMERA_IP:554/h264Preview_01_main
        #   roles: [record]
    # Also disable Frigate's recorder since SS does it:
    record:
      enabled: false
    snapshots:
      enabled: true   # keep AI event snapshots (small, useful for debugging)
```

This reduces disk usage on the Docker host — recording stays on Synology where you
already have it.

### Verifying camera supports multi-client RTSP

If both Surveillance Station and Frigate get "stream lost" or "max clients exceeded":

1. Check camera's web UI → **Stream / RTSP settings** → look for "Max clients" or "Concurrent sessions"
2. Try increasing limit (some Reolink models default to 2; max usually 4)
3. If camera firmware doesn't allow >1 client, switch to **Option B**

### What you get

- ✅ Surveillance Station continues recording as before (zero changes there)
- ✅ Frigate adds AI zone detection + WhatsApp/Telegram alert
- ✅ HA dashboard with parking status
- ✅ No additional camera load (Frigate uses already-broadcast streams)

---

## Option B — Surveillance Station RTSP restream

When camera doesn't support multiple clients (or you want centralized stream
management), use Synology's built-in RTSP server to **restream** the camera feed.

### Architecture

```
                                                       ┌─→ Surveillance Station services (recording, AI, mobile app, etc)
[Reolink Camera] ──RTSP─→ [Synology RTSP server] ──────┤
                                                       └─→ RTSP restream → [Frigate]
                                                                                 │
                                                                                 ▼
                                                                             [HA + WhatsApp]
```

Only ONE connection from camera (to Synology). Frigate (and other clients) read
from Synology's restream URL.

### Setup steps

#### 1. Enable RTSP server in Surveillance Station

1. Open **Surveillance Station** web UI
2. **Settings** → **Surveillance Station Server** → **Live View**
3. Check **"Enable RTSP Server"**
4. **Save**

#### 2. Get the restream URL

The URL format depends on Surveillance Station version:

**Surveillance Station 9.x+:**
```
rtsp://<synology-ip>:554/Sms=<smartstream-id>
```

**Older versions:**
```
rtsp://<synology-ip>:554/<camera-name>
rtsp://<synology-ip>:554/<dsm-username>?camera=<camera-id>
```

To find exact URL:
1. **Surveillance Station** → **IP Camera** → click your camera
2. **Edit** → **Information** tab → look for "RTSP URL" field
3. Copy the value

If not visible, query via API:
```bash
curl "http://<synology>:5000/webapi/entry.cgi?api=SYNO.SurveillanceStation.Camera&method=List&version=9"
```

Look for `liveStream.url` in the JSON response.

#### 3. Update Frigate config

Edit `config/frigate.yml` — replace the RTSP URLs with Synology restream:

```yaml
cameras:
  parking:
    ffmpeg:
      inputs:
        - path: rtsp://SYNOLOGY_IP:554/SmartStream_ID_HERE
          roles: [detect, record]
    # Frigate now sees the same stream Surveillance Station broadcasts
```

#### 4. Test connection

From the Docker host:
```bash
docker run --rm linuxserver/ffmpeg:latest \
  -rtsp_transport tcp -i "rtsp://<synology-ip>:554/<stream>" \
  -frames:v 1 -f null - 2>&1 | grep "Stream #"
```

Should print video stream details. If "Connection refused" or "401" — check
Surveillance Station server config + your stream URL.

#### 5. Restart Frigate

```bash
docker compose restart frigate
```

### Pros & cons

✅ **Pros:**
- Single connection from camera (works with restrictive cameras)
- Surveillance Station fully controls camera (mobile app, recording quality, schedules)
- Frigate gets identical stream to what Surveillance Station shows

⚠️ **Cons:**
- Adds ~200ms latency (extra restream hop)
- Synology CPU does the restreaming (small overhead, ~2-5% per camera)
- If Synology reboots or Surveillance Station restarts, Frigate loses stream until it recovers

### What you get

Same as Option A, but with stream management centralized on Synology.

---

## Option C — Use Surveillance Station AI instead

Synology Surveillance Station has **DeepVideo Analytics** (DVA) built-in for
recent DSM versions. If you already have **Device Licenses** for your cameras,
you can use SS's AI directly + integrate with Home Assistant — no Frigate needed.

### Architecture

```
[Cameras] → [Surveillance Station + DeepVideo] ──webhook──→ [HA] ──→ WhatsApp
```

### Setup steps

#### 1. Verify DeepVideo Analytics is available

1. **Surveillance Station** → **DeepVideo Analytics**
2. If grayed out, it's available on:
   - Plus / Value+ / XS models (DS920+, DS1522+, DS1821+, etc.)
   - Requires DSM 7.0+
   - Requires Surveillance Station 9.0+
3. Some models can run DVA only on cameras with **AI label** in Synology compat list

#### 2. Configure detection in Surveillance Station

1. **DeepVideo Analytics** → **Add DVA Task**
2. **Target camera:** select your parking camera
3. **Analysis type:** **Intrusion Detection** OR **Object Tracking**
4. **Configure region of interest** — draw your parking spot zone
5. **Object class:** **Vehicle**
6. **Save** — DVA begins detecting

#### 3. Set up Action Rule for "spot empty" detection

This is the tricky part — SS DVA fires on **detection**, not on **absence**. To
detect "spot empty," use **timer + state tracking**:

1. **Surveillance Station** → **Action Rule** → **Add Rule**
2. **Event source:** DVA → **Vehicle leaves zone**
3. **Action:** **HTTP Request** → POST to HA webhook
   - URL: `http://<ha-host>:8123/api/webhook/parking_spot_changed`
   - Method: POST
   - Body: `{"action": "left", "camera": "parking"}`
4. **Save**

#### 4. HA webhook automation

In `config/homeassistant/automations.yaml`:

```yaml
- id: parking_spot_free_from_ss
  alias: "🅿️ Parking spot free (via Surveillance Station)"
  trigger:
    - platform: webhook
      webhook_id: parking_spot_changed
      allowed_methods: [POST]
      local_only: true
  condition:
    - "{{ trigger.json.action == 'left' }}"
  action:
    # Wait 2 min to debounce (same anti-blink pattern as Frigate)
    - delay: "00:02:00"
    - service: notify.whatsapp_parking
      data:
        message: >
          🅿️ Parking spot FREE (Surveillance Station detection)!
          Time: {{ now().strftime('%H:%M') }}
```

#### 5. Add Surveillance Station camera entities to HA

Open HA → **Settings → Devices & Services → Add Integration** → search **"Synology DSM"** → enter Synology IP + credentials.

This adds all SS cameras as HA `camera.*` entities. You can build dashboards with
live feeds without Frigate.

### Pros & cons

✅ **Pros:**
- Zero extra containers — just HA + Surveillance Station
- One AI platform to manage (Surveillance Station)
- Native HA integration for live camera feeds
- SS DVA models trained specifically for security/surveillance scenarios

⚠️ **Cons:**
- **Requires Synology Device Licenses** for cameras beyond first 2 (~€30 per camera one-time)
- DeepVideo Analytics is restricted to higher-end Synology models
- Less tunable than Frigate (zones are fixed, can't adjust detection confidence per object class)
- "Spot empty" detection is a workaround (intrusion + delay + state tracking) — Frigate handles this natively
- No Frigate UI for debugging detections — must use Surveillance Station's interface

### What you get

- ✅ Parking detection running on existing Synology infrastructure
- ✅ HA Companion App / WhatsApp / Telegram alerts via HA automation
- ❌ No Frigate-style zone occupancy persistence (DVA fires on motion, not state)
- ❌ Limited to SS's AI capabilities (no YOLOv8 custom models)

---

## Decision tree

```
Do you want maximum detection accuracy + flexibility?
├── YES → Use Frigate (Option A or B)
│         Choose between A (co-existence) and B (restream)
│         based on whether your camera supports >1 RTSP client
│
└── NO  → Are you willing to pay for Synology Device Licenses?
           ├── YES → Option C (use existing SS infrastructure)
           └── NO  → Use Frigate with Option A (recommended)
```

---

## FAQ

### Will Frigate "steal" the stream from Surveillance Station?

**No.** Cameras serve multiple RTSP clients independently. Surveillance Station
and Frigate each maintain their own connection. Bandwidth usage on the camera
increases slightly per concurrent client.

### Can I use Frigate AND Surveillance Station DVA on the same camera?

**Yes**, but it's overkill and may double-trigger alerts. Pick one AI system
(Frigate for parking, SS DVA for general security, or split per camera).

### My camera doesn't support 2 RTSP clients — what do I do?

Use **Option B** (Surveillance Station restream). The camera sees only one
connection (from Synology), and Synology serves multiple clients including
Frigate.

### Does this affect Surveillance Station recording quality?

**No, in Option A and B**. Surveillance Station continues recording the main
stream at full quality. Frigate uses the sub stream which is independent.

### What about Synology Mobile app and Live View?

**Unchanged.** Mobile app and Live View use Surveillance Station's own streaming
infrastructure (which uses the main stream). Frigate's sub-stream consumption
is invisible to other Surveillance Station clients.

### Disk usage concerns

- **Option A:** Frigate writes its own short clips for AI events (~1-5 MB per event).
  You can disable Frigate recording (`record.enabled: false`) since SS already records.
- **Option B:** Same as A.
- **Option C:** Only Surveillance Station writes recordings (your existing setup).

For dedicated parking-only Frigate usage, set in `config/frigate.yml`:
```yaml
record:
  enabled: false
snapshots:
  enabled: true
  retain:
    default: 3   # keep snapshots 3 days for debugging
```

This minimizes Frigate's disk footprint to a few MB/day.

---

## Related guides

- [Installation Guide](INSTALLATION.md) — main setup
- [User Guide](USER_GUIDE.md) — daily operations
- [Synology NAS deployment](nas/synology.md) — running this whole stack on Synology
- [Multi-camera example](../examples/multi-camera/README.md) — multiple cameras setup
