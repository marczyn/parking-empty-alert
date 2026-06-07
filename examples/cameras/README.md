# 📷 Non-Reolink camera templates

This project defaults to Reolink, but **any RTSP camera** works. This directory has tested templates for the most popular non-Reolink brands.

## Quick lookup

| Your camera | Template | Notes |
|---|---|---|
| Reolink (any model) | base `config/frigate.yml` | Default — no changes needed |
| **Hikvision** (DS-2CD, DarkFighter, ColorVu) | [hikvision.yml](#hikvision) | Most common globally |
| **Dahua** (IPC-HFW, IPC-HDW, Lite, Pro) | [dahua.yml](#dahua--amcrest) | Common in commercial deployments |
| **Amcrest** | [dahua.yml](#dahua--amcrest) | Rebranded Dahua — same RTSP |
| **Annke** | [hikvision.yml](#hikvision) | Rebranded Hikvision — same RTSP |
| **UniFi Protect** (G3/G4/G5, AI cameras) | [unifi-protect.yml](#unifi-protect) | Requires UniFi Protect controller |
| **TP-Link Tapo** (C100, C200, C310, C320WS) | [tp-link-tapo.yml](#tp-link-tapo) | Consumer market, RTSP via "third-party access" |
| **TP-Link Vigi** | [generic-onvif.yml](#generic-onvif) | Use ONVIF |
| **Axis** (M-series, P-series, Q-series) | [generic-onvif.yml](#generic-onvif) | Use ONVIF / pre-2010 use VAPIX |
| **Wyze** (Cam v2/v3 with RTSP firmware) | [generic-onvif.yml](#generic-onvif) | Requires custom RTSP firmware |
| **Eufy** (some models) | [generic-onvif.yml](#generic-onvif) | RTSP support varies by model |
| **Foscam** | [generic-onvif.yml](#generic-onvif) | Use ONVIF |
| **Anything else** | [generic-onvif.yml](#generic-onvif) | ONVIF auto-discovery covers most |

## How to use a template

1. Find your camera brand in the table above → note the template name
2. Copy the corresponding `.yml` file from this directory
3. Open `config/frigate.yml`
4. Find the `cameras:` section
5. **Replace ONLY the `ffmpeg.inputs` paths** with values from the template
6. Keep everything else (zones, objects, snapshots) — they're camera-agnostic
7. Restart Frigate: `docker compose restart frigate`

## Universal tips for any camera

### Find the RTSP URL

**Method 1 — Vendor docs (most reliable):**
Search "<brand> <model> RTSP URL" in vendor docs.

**Method 2 — ONVIF Device Manager (universal):**
```bash
docker run --rm -it --network host \
  ghcr.io/azanto/onvif-tool discovery
```
Lists all ONVIF cameras on your LAN with their RTSP URLs.

**Method 3 — Brand-specific tools:**
- **Hikvision:** `iVMS-4200` or `SADP Tool`
- **Dahua:** `Smart PSS` or `ConfigTool`
- **Axis:** `AXIS IP Utility`

**Method 4 — Test with ffmpeg:**
```bash
# Try common URLs:
for path in "Streaming/Channels/101" "Streaming/Channels/102" \
            "cam/realmonitor?channel=1&subtype=0" "live/ch00_0" \
            "stream0" "stream1" "live.sdp" "h264.sdp" "video.sdp"; do
  url="rtsp://USER:PASS@CAMERA_IP:554/${path}"
  echo -n "Testing: ${path} → "
  if timeout 5 docker run --rm linuxserver/ffmpeg:latest \
       -rtsp_transport tcp -i "$url" -frames:v 1 -f null - 2>&1 | grep -q "Stream #"; then
    echo "✓ WORKS"
  else
    echo "fail"
  fi
done
```

### Common ports

| Protocol | Port |
|---|---|
| RTSP | 554 (most cameras) |
| RTSP over HTTP | 8080 |
| RTSP over HTTPS | 443 |
| ONVIF | 80 or 8080 |
| HTTP (web UI) | 80 |
| HTTPS (web UI) | 443 |

If port 554 doesn't respond, check the camera's web UI **Settings → Network → Ports**.

### Sub-stream (low-res) vs Main-stream (high-res)

Almost every IP camera has at least 2 streams:
- **Sub stream** (also "second stream", "stream2") — low resolution (~640×360 to 720p), lower bitrate
- **Main stream** (also "primary", "stream1") — full HD or 4K

For Frigate, use:
- **Sub** for `roles: [detect]` (AI runs on this, saves CPU)
- **Main** for `roles: [record]` (high quality recording)

Some cameras also have a 3rd stream — use for substream if it's smaller.

### Codec (H.264 vs H.265)

| Codec | Pros | Cons |
|---|---|---|
| **H.264** (AVC) | Universal support, lower CPU decode | Larger file sizes |
| **H.265** (HEVC) | 30-50% smaller files | Higher decode CPU, less FFmpeg compatibility |

**Recommendation:** Set both streams to **H.264** in camera UI. Avoids surprises.

If you must use H.265, comment out h264 paths in templates and uncomment h265 variants (templates include both).

### Authentication failures

If you get `401 Unauthorized`:
1. Verify username/password in camera web UI
2. Some cameras require **separate RTSP credentials** (not web UI credentials) — check camera "Streaming" settings
3. Special characters in password (`@`, `:`, `/`) must be URL-encoded:
   - `@` → `%40`
   - `:` → `%3A`
   - `/` → `%2F`
   - `&` → `%26`
   - Or simpler: change password to alphanumeric

### Performance tuning per vendor

Some cameras have quirks:

| Camera | Quirk | Fix |
|---|---|---|
| Old Hikvision firmware | Sends B-frames out of order | `hwaccel_args: preset-vaapi -avoid_negative_ts make_zero` |
| Dahua varifocal | Auto-focus pumps every minute | Lock focus in camera UI |
| TP-Link Tapo | Sub-stream limited to 360p | Use main stream for both detect + record |
| Wyze (custom RTSP) | RTSP server crashes hourly | Add Frigate ffmpeg `reconnect: 1` |
| Axis | Long URL paths | Use ONVIF profile name |

---

## Hikvision

[hikvision.yml](hikvision.yml)

Tested with: DS-2CD2032, DS-2CD2143G2, DS-2CD2143G2-IU, DS-2DE3, DarkFighter series, ColorVu series.

**Default RTSP URL pattern:**
```
rtsp://USER:PASS@IP:554/Streaming/Channels/{ch}{stream}
```
- `{ch}` = channel number (1-N for NVR, 1 for single camera)
- `{stream}` = `01` (main) or `02` (sub)

**Examples:**
- Single camera, main: `rtsp://admin:pass@192.168.1.100:554/Streaming/Channels/101`
- Single camera, sub: `rtsp://admin:pass@192.168.1.100:554/Streaming/Channels/102`
- NVR channel 3, main: `rtsp://admin:pass@192.168.1.50:554/Streaming/Channels/301`

**Sub-stream resolution:**
Configure in web UI → Configuration → Image → Stream Settings → Sub-stream.

---

## Dahua / Amcrest

[dahua.yml](dahua.yml)

Tested with: IPC-HFW2231, IPC-HDW3441, IPC-HDW5849, Amcrest IP4M-1051W, IP8M-2493.

**Default RTSP URL pattern:**
```
rtsp://USER:PASS@IP:554/cam/realmonitor?channel={ch}&subtype={stream}
```
- `{ch}` = channel number (1 for single camera, 1-N for NVR)
- `{stream}` = `0` (main) or `1` (sub)

**Examples:**
- Main: `rtsp://admin:pass@192.168.1.100:554/cam/realmonitor?channel=1&subtype=0`
- Sub: `rtsp://admin:pass@192.168.1.100:554/cam/realmonitor?channel=1&subtype=1`

**Important:** Dahua often requires admin password to be set **before** RTSP works. Cannot use blank password.

---

## UniFi Protect

[unifi-protect.yml](unifi-protect.yml)

Tested with: G3, G3 Flex, G3 Bullet, G4 Pro, G4 Doorbell, AI 360, AI Bullet.

**Setup:**
1. Open UniFi Protect web UI → Settings → System → RTSP (or per-camera Settings → Stream)
2. Enable RTSP streams for the camera
3. For each stream (High/Medium/Low), copy the URL — looks like:
   ```
   rtsp://192.168.1.1:7447/abcdef1234567890
   ```
4. UniFi Protect uses a **stream key** (not username/password) and a non-standard port (7447)

**Note:** UniFi Protect URLs change if you re-enable RTSP. Save them after first setup.

---

## TP-Link Tapo

[tp-link-tapo.yml](tp-link-tapo.yml)

Tested with: C100, C110, C200, C210, C310, C320WS.

**Setup steps:**
1. Open Tapo app → Camera → Camera Settings → Advanced Settings → Camera Account
2. Create a dedicated "third-party access" account (separate from your TP-Link cloud account)
3. Use that account for Frigate

**Default RTSP URL pattern:**
```
rtsp://USER:PASS@IP:554/stream1   # main (1080p)
rtsp://USER:PASS@IP:554/stream2   # sub (360p, sometimes limited)
```

**Important:** Tapo sub-stream is sometimes limited to 360p15. If your detection is poor, use stream1 for both detect + record.

---

## Generic ONVIF

[generic-onvif.yml](generic-onvif.yml)

Use this template when:
- Your camera supports ONVIF but you don't know the exact RTSP URL
- Vendor-specific template doesn't exist (Foscam, Wyze, Eufy, no-name Chinese cameras)
- ONVIF discovery returns a stream URL

**Discovery:**
```bash
docker run --rm -it --network host \
  --entrypoint /onvif-tool ghcr.io/azanto/onvif-tool discovery
```

Returns URLs like:
```
rtsp://192.168.1.100:554/onvif-media/media.amp?profile=profile_1_h264&sessiontimeout=60&streamtype=unicast
```

Paste those URLs directly into the template.

---

## Camera positioning for parking detection

Regardless of brand, these tips apply:

### Optimal angle

- **Top-down 30-45°** angle: best balance of car visibility + parking lines
- **Side angle:** ok, but plate hard to read for LPR
- **Top-down 90°** (bird's eye): great for occupancy, useless for LPR

### Distance

- **5-15m** away: optimal for 1 spot, supports LPR
- **15-25m** away: good for 1 spot, LPR may struggle
- **25-30m** away: still works for occupancy, LPR fails
- **30m+** away: car gets <50px tall, detection accuracy drops

### Field of View (FoV)

- **1 spot:** any standard lens (60-90° FoV) works
- **3-5 spots:** wide-angle lens (90-110° FoV)
- **5-15 spots:** ultra-wide-angle (110-180° FoV) or fish-eye
- **15+ spots:** PTZ camera with auto-tracking, or multiple cameras

### Lighting

- **Daytime:** any camera works
- **Night:** IR cameras (most modern outdoor IP cameras have IR LEDs)
- **Mixed:** ColorVu (Hikvision) or Color Night Vision (Dahua) maintain color in low light
- **24/7 evidence-quality:** add external floodlight aimed at parking spots

### Weather protection

For outdoor:
- **IP66 or higher** rating
- **Junction box** for cable connection (water/rodent protection)
- **Heater** (built-in or aftermarket) for sub-zero temperatures
- **Sun shield** for tropical climates (prevents thermal shutdown)

---

## Contributing a new camera template

If your camera works but isn't in this list:

1. Open an [issue](https://github.com/marczyn/parking-empty-alert/issues/new?template=feature_request.md) with title `[Camera template] <Brand> <Model>`
2. Include:
   - Brand + model + firmware version
   - Working RTSP URL pattern
   - Any quirks you encountered
3. Or submit a PR adding `examples/cameras/<brand>.yml`

We accept any vendor whose RTSP is well-documented.
