# User Guide

This guide covers everything **after installation**: daily operation, customization, advanced features, troubleshooting.

For initial setup see [Installation Guide](INSTALLATION.md).

---

## Table of contents

1. [Daily operation](#1-daily-operation)
2. [What to expect](#2-what-to-expect)
3. [Reading Frigate UI](#3-reading-frigate-ui)
4. [Reading Home Assistant](#4-reading-home-assistant)
5. [Tuning detection](#5-tuning-detection)
6. [Customizing alerts](#6-customizing-alerts)
7. [Advanced: scheduled quiet hours](#7-advanced-scheduled-quiet-hours)
8. [Advanced: multiple recipients](#8-advanced-multiple-recipients)
9. [Advanced: Telegram alternative](#9-advanced-telegram-alternative)
10. [Multi-camera setup](#10-multi-camera-setup)
11. [Backup and restore](#11-backup-and-restore)
12. [Updates](#12-updates)
13. [Health monitoring](#13-health-monitoring)
14. [Privacy and security](#14-privacy-and-security)
15. [Performance tuning](#15-performance-tuning)
16. [Troubleshooting](#16-troubleshooting)
17. [FAQ](#17-faq)

---

## 1. Daily operation

After successful install, the system runs **fully autonomously**:

- **24/7 monitoring** — Frigate processes camera frames continuously
- **No manual intervention** needed for normal operation
- **Alerts arrive within ~2 minutes** of the parking spot becoming empty
- **All data stays local** — only WhatsApp messages leave your network (via CallMeBot)

You typically interact with the system only when:
- 📱 You receive a WhatsApp alert → drive to the spot
- 🐛 You want to adjust sensitivity (false positives/negatives)
- 📷 You add a 2nd camera
- 🔄 You update Docker images periodically

---

## 2. What to expect

### Normal flow

```
Time  | Event                              | State                    | Notification
------|-----------------------------------|--------------------------|------------------
08:00 | Owner parks car                   | sensor.parking_car = 1   | (none)
08:00 | Frigate persistent tracking       | sensor.parking_car = 1   | (none)
17:30 | Owner drives car away             | sensor.parking_car = 0   | (none, waiting)
17:32 | 2-min wait elapsed                | sensor.parking_car = 0   | 🅿️ WhatsApp: SPOT FREE!
17:35 | Different car parks               | sensor.parking_car = 1   | (none)
17:35 | Anti-blink: ignore brief noise    | sensor.parking_car = 1   | (none)
```

### What you receive

```
🅿️ Parking spot FREE!
You can park — became free 2 min ago.
Time: 17:32
```

### What you do NOT receive

- Alerts every time motion is detected (would be spam)
- Alerts for adjacent spots (only the zone you drew)
- Alerts if the car briefly drives through without parking (anti-blink)
- Alerts at night if you set up quiet hours (see [section 7](#7-advanced-scheduled-quiet-hours))

---

## 3. Reading Frigate UI

Open `http://<your-docker-host-IP>:5000`.

### Main sections

| Section | What it shows | When to use |
|---|---|---|
| **Live** | Real-time camera streams | Visual sanity check, see what camera sees right now |
| **Events** | All detection events with snapshots | Review past detections, false positives, see why an alert fired (or didn't) |
| **Recordings** | Full timeline of recorded video | Watch back specific time periods (legal evidence, accidents) |
| **Debug** | Live view with overlays (bounding boxes, zones, motion) | **Most useful for tuning** — see exactly what Frigate detects in real time |
| **Settings** | Camera configs, zones editor | Adjust zones, masks |

### Useful Debug overlays

In Debug view, toggle:
- ✅ **Bounding boxes** — see Frigate's object detections (cars, people, etc.)
- ✅ **Zones** — see your parking_spot polygon overlay
- ✅ **Motion** — see motion-detection regions (red boxes)
- ✅ **Timestamp** — confirms live feed isn't frozen
- ⬜ **Mask** (optional) — see ignored regions

### Events page filters

To find specific events:
- **Cameras:** `parking`
- **Labels:** `car`, `truck`, `motorcycle`
- **Zones:** `parking_spot`
- **Time range:** last 24h, last 7 days, custom

Each event shows:
- 📸 Snapshot at detection moment
- 🎬 Click → full video clip
- 📊 Tracker history (how long it was visible)
- 🎯 Bounding box overlay

---

## 4. Reading Home Assistant

Open `http://<your-docker-host-IP>:8123`.

### Key entities

The automation uses **`sensor.parking_parking_spot_car`** — the integer count of cars in the zone.

| State | Meaning |
|---|---|
| `0` | Spot is empty |
| `1` | One car is parked (normal case) |
| `2` or more | Two cars partially overlapping the zone (rare, indicates bad zone or oversized polygon) |
| `unavailable` | Frigate is down or MQTT lost — restart stack |

### Useful HA pages

| Page | Path | What it shows |
|---|---|---|
| Dashboard | `/lovelace/0` | Default view |
| History | `/history` | Plot of `sensor.parking_parking_spot_car` over time |
| Logbook | `/logbook` | All state changes + automation triggers |
| Automations | `/config/automation/dashboard` | Toggle alerts on/off, see last triggered time |
| Developer Tools → States | `/developer-tools/state` | Current value of every entity |
| Developer Tools → Services | `/developer-tools/service` | Test `notify.whatsapp_parking` manually |

### Quick dashboard card (optional)

To add a parking status card to the dashboard:

1. **Overview → Edit Dashboard (top-right pencil icon)**
2. **+ Add Card → Entities**
3. Add these entities:
   - `sensor.parking_parking_spot_car`
   - `binary_sensor.parking_motion`
   - `camera.parking`
   - `image.parking_parking_spot`
4. **Save**

You now have a card showing live parking spot status.

---

## 5. Tuning detection

### Symptom: too many false alerts ("spot free" but car still there)

**Possible causes:**
1. Camera shake/wind moves view of car
2. Car partially covered by shadow → YOLO loses confidence
3. Zone polygon too small (car edge outside polygon)

**Fixes:**

**A) Increase `inertia`** (how many frames object must stay in zone):

In `config/frigate.yml`:
```yaml
zones:
  parking_spot:
    inertia: 5     # was 3 — more frames required
```

**B) Increase `max_disappeared`** (how long can car "disappear" before Frigate forgets):

```yaml
detect:
  max_disappeared: 50    # was 25 — 10s tolerance
```

**C) Lower YOLO confidence threshold**:

```yaml
objects:
  filters:
    car:
      min_score: 0.4     # was 0.5
      threshold: 0.6     # was 0.7
```

**D) Increase alert delay**:

In `config/homeassistant/automations.yaml`:
```yaml
for:
  minutes: 5     # was 2 — wait longer before alerting
```

Restart Frigate: `docker compose restart frigate`
Reload HA automations: HA UI → Developer Tools → YAML → Reload Automations

### Symptom: alerts never come (spot becomes empty, no WhatsApp)

**Diagnostic flow:**

1. **HA Developer Tools → States** → check `sensor.parking_parking_spot_car`:
   - Is it `0` when spot is empty? → If yes, problem is HA automation. If no, problem is Frigate detection.

2. **Frigate problem** (sensor stays at 1):
   - Frigate Debug → does YOLO detect a stale "ghost" car? → Increase `stationary.max_frames` from `0` to a smaller value like `1000` (clears after 1000 frames = ~3 min)

3. **HA automation problem** (sensor goes to 0 but no alert):
   - HA → Automations → "🅿️ Parking spot empty → WhatsApp" → check **Last triggered** time
   - If last triggered is recent → automation fired, problem is CallMeBot/WhatsApp delivery
   - If last triggered is old → automation not firing — check that the automation toggle is **enabled** + condition met for the full `for: minutes: 2`

4. **WhatsApp delivery problem**:
   - HA → Developer Tools → Services → `notify.whatsapp_parking` → send test → does it arrive?
   - If no → CallMeBot APIKEY issue (re-check `secrets.yaml`)

### Symptom: false positives (spot detected as empty when there IS a car)

**Cause:** YOLO miss-detection. Car is shadowed, partially behind a tree, parked at an angle YOLO doesn't recognize.

**Fixes:**

**A) Improve camera placement:**
- Higher angle (look down at car, not side-on)
- Better lighting (add IR illuminator for night, or floodlight)
- Closer to spot (20m is OK, 30m+ is hard)

**B) Add HA condition:**

Make the alert only fire if it's also evening (cars usually leave during day):

```yaml
- id: parking_spot_free_alert
  trigger: ...
  condition:
    - condition: time
      after: "17:00"
      before: "22:00"
  action: ...
```

---

## 6. Customizing alerts

### Change alert text

`config/homeassistant/automations.yaml`:

```yaml
- service: notify.whatsapp_parking
  data:
    message: >
      🅿️ Your custom message here.
      Time: {{ now().strftime('%H:%M') }}
      Day: {{ now().strftime('%A') }}
```

Available template variables:
- `{{ now().strftime('%H:%M') }}` → current time, e.g., `17:32`
- `{{ now().strftime('%Y-%m-%d') }}` → date, e.g., `2026-06-07`
- `{{ states('sensor.parking_parking_spot_car') }}` → current car count

### Add "spot just got taken" alert

In `automations.yaml`, uncomment the `parking_spot_taken_alert` block (it's there but commented out by default).

### Change wait time

```yaml
for:
  minutes: 2    # change to 5 for less spammy, 1 for faster
```

### Add cooldown (avoid double-firing)

If you also enable the "taken" alert, sometimes a car comes and goes triggering both alerts. Add cooldown:

```yaml
- id: parking_spot_free_alert
  trigger: ...
  mode: single                         # already there
  max_exceeded: silent
  action: ...
  # After action runs, can't fire again for 5 min:
  variables:
    cooldown: "5"
```

---

## 7. Advanced: scheduled quiet hours

You don't want WhatsApp at 3 AM. Add a `condition` block:

```yaml
- id: parking_spot_free_alert
  alias: "🅿️ Parking spot empty → WhatsApp"
  mode: single
  trigger:
    - platform: numeric_state
      entity_id: sensor.parking_parking_spot_car
      below: 1
      for: {minutes: 2}
  condition:
    - condition: time
      after: "07:00"
      before: "22:00"
    - condition: time
      weekday:
        - mon
        - tue
        - wed
        - thu
        - fri
  action: ...
```

This sends alerts only **weekdays, 07:00-22:00**.

---

## 8. Advanced: multiple recipients

Want alerts on multiple phones? CallMeBot is single-recipient per API call, but you can chain:

In `automations.yaml`:

```yaml
- id: parking_spot_free_alert
  trigger: ...
  action:
    - service: notify.whatsapp_parking
      data:
        message: "🅿️ Parking spot FREE!"
    # Add 2nd recipient (their phone + their APIKEY)
    - service: rest_command.whatsapp_send
      data:
        phone: "48502222222"
        apikey: "1234568"
        message: "🅿️ Parking spot FREE!"
    # Add 3rd recipient
    - service: rest_command.whatsapp_send
      data:
        phone: "48503333333"
        apikey: "1234569"
        message: "🅿️ Parking spot FREE!"
```

**Each phone must independently authorize CallMeBot** (each person sends "I allow callmebot to send me messages" from their own WhatsApp).

---

## 9. Advanced: Telegram alternative

If CallMeBot is unreliable for you, Telegram works as a free alternative:

### Setup BotFather

1. Open Telegram → search `@BotFather`
2. Send `/newbot`
3. Choose a name (e.g., "Parking Alerts")
4. Choose a username (e.g., "my_parking_alerts_bot")
5. BotFather replies with a `TOKEN` like `123456789:ABCdef...`
6. Search your bot → start chat → send `/start`

### Get your chat ID

```bash
curl "https://api.telegram.org/bot<TOKEN>/getUpdates"
```

Find `"chat":{"id":123456789` in the response — `123456789` is your chat ID.

### Add to HA

`config/homeassistant/configuration.yaml`:

```yaml
telegram_bot:
  - platform: polling
    api_key: !secret telegram_token
    allowed_chat_ids:
      - !secret telegram_chat_id

notify:
  - name: telegram_parking
    platform: telegram
    chat_id: !secret telegram_chat_id
```

`config/homeassistant/secrets.yaml`:

```yaml
telegram_token: "123456789:ABCdef..."
telegram_chat_id: 123456789
```

Then in `automations.yaml`, use `notify.telegram_parking` instead of (or alongside) `notify.whatsapp_parking`.

---

## 10. Multi-camera setup

To monitor N parking spots with N cameras, use the multi-camera example:

```bash
cp examples/multi-camera/frigate.yml      config/frigate.yml
cp examples/multi-camera/automations.yaml config/homeassistant/automations.yaml
```

Then edit IPs in the new `config/frigate.yml`. See [examples/multi-camera/README.md](../examples/multi-camera/README.md) for full details.

---

## 11. Backup and restore

### Backup

```bash
cd parking-empty-alert
tar czf ~/parking-backup-$(date +%Y%m%d).tar.gz \
  .env \
  config/ \
  docker-compose.yml
```

Store the resulting `.tar.gz` somewhere safe (cloud, external drive).

**Do not commit `.env` or `secrets.yaml` to git!**

### Restore

```bash
# Fresh Docker host
cd ~
mkdir parking-empty-alert && cd parking-empty-alert
tar xzf ~/parking-backup-20260607.tar.gz
docker compose up -d
```

### What you lose without backup

- `.env` and `config/homeassistant/secrets.yaml` — would need to re-run `setup.sh`
- Recorded video footage in `/var/lib/docker/volumes/parking-empty-alert_frigate-storage/` — not backed up by default (large)

To backup recordings too:
```bash
docker run --rm \
  -v parking-empty-alert_frigate-storage:/data \
  -v $PWD:/backup \
  alpine \
  tar czf /backup/frigate-recordings-$(date +%Y%m%d).tar.gz /data
```

---

## 12. Updates

### Update Docker images

```bash
cd parking-empty-alert
git pull                  # update repo to latest
docker compose pull       # pull latest stable images (Frigate, HA, Mosquitto)
docker compose up -d      # restart with new images
```

Check Frigate release notes: https://github.com/blakeblackshear/frigate/releases
Check HA release notes: https://www.home-assistant.io/blog/

### Subscribe to repo notifications

```bash
gh repo watch marczyn/parking-empty-alert
```

Or watch via GitHub web UI for releases.

---

## 13. Health monitoring

### Check stack is healthy

```bash
docker compose ps                              # all 3 should be "healthy" or "Up"
docker stats --no-stream                       # CPU/RAM usage
df -h /var/lib/docker                          # disk space
```

### Detect "Frigate stopped working" early

Add a watchdog automation in HA that alerts if Frigate state is `unavailable` for >10 min:

```yaml
- id: frigate_offline_alert
  alias: "⚠️ Frigate offline"
  trigger:
    - platform: state
      entity_id: binary_sensor.parking_motion
      to: "unavailable"
      for: {minutes: 10}
  action:
    - service: notify.whatsapp_parking
      data:
        message: "⚠️ Frigate offline >10 min. Check Docker host."
```

### Logs

```bash
docker compose logs -f frigate         # Frigate live logs
docker compose logs --tail 100 homeassistant
docker compose logs --tail 100 mosquitto
```

---

## 14. Privacy and security

### What data leaves your network

- ✅ **WhatsApp messages** → CallMeBot → WhatsApp servers (Meta/Facebook)
  - Message content: only the alert text you configure ("🅿️ Parking spot FREE!")
  - Frequency: per alert (a few per day at most)
  - **No images, no video, no metadata** beyond the message text
- ✅ Docker image pulls from Docker Hub / GitHub Container Registry (anonymous, one-way)

### What data stays local

- 📹 All camera video (recordings, snapshots)
- 🤖 All AI detection happens on YOUR hardware
- 💾 All Frigate events stay on your disk
- 🗣 All MQTT traffic on local network
- 🏠 Home Assistant local install

### Camera credentials

- Reolink password is in `.env` and `docker-compose.yml` (env var) — keep these files **mode 600** (`chmod 600 .env`)
- The `frigate` Reolink user has **Viewer** permission only — can't change camera settings
- If the host is compromised, attacker gets Reolink Viewer access (not admin)

### Network exposure

Default ports exposed by `docker-compose.yml`:
- `5000` Frigate UI
- `8123` Home Assistant UI
- `1883` MQTT
- `8554-8555` Frigate RTSP/WebRTC restream

**For LAN-only use** these are fine. **For internet access** to HA UI:
- ❌ **DO NOT** port-forward 8123 directly — HA + your home network at risk
- ✅ Use **Home Assistant Cloud (Nabu Casa)** — official, encrypted, $6.5/mo
- ✅ Use **VPN** (WireGuard, Tailscale) — free, encrypted
- ✅ Use **Cloudflare Tunnel** — free, encrypted

---

## 15. Performance tuning

### Reduce CPU usage

**Option A:** Lower detection FPS

`config/frigate.yml`:
```yaml
detect:
  fps: 3    # was 5 — saves CPU, slower reaction
```

**Option B:** Use hardware acceleration

See README → "Hardware acceleration" table.

**Option C:** Reduce sub-stream resolution

In Reolink camera UI: Sub Stream → `480 × 270` instead of `640 × 360`. Reduces decode CPU.

### Reduce RAM usage

Default config uses ~1.5 GB RAM total. To reduce:

```yaml
# In docker-compose.yml, reduce Frigate cache:
- type: tmpfs
  target: /tmp/cache
  tmpfs:
    size: 500000000   # 500 MB instead of 1 GB
```

### Reduce disk usage

```yaml
# In config/frigate.yml:
record:
  retain:
    days: 1            # was 3 — 3× less video
snapshots:
  retain:
    default: 3         # was 7 — fewer event snapshots
```

---

## 16. Troubleshooting

See [INSTALLATION.md → Common installation issues](INSTALLATION.md#11-common-installation-issues) for install-time problems.

### Runtime problems

#### Problem: stack worked, now no alerts come

**Quick check (5 min):**

```bash
# All running?
docker compose ps

# Camera reachable?
docker exec frigate ping -c 3 <camera_ip>

# Frigate sees motion?
docker compose logs frigate | tail -50 | grep -i "object detected"

# MQTT messages flowing?
docker exec mosquitto mosquitto_sub \
  -u frigate -P "$(grep MQTT_PASSWORD .env | cut -d= -f2)" \
  -t 'frigate/#' -C 5 -W 10

# HA automation enabled?
# HA UI → Automations → "🅿️ Parking spot empty" → must be ON
```

#### Problem: WhatsApp delivery delayed >1 min

**Cause:** CallMeBot rate limit (1 msg/min/phone)

**Fix:** Don't trigger multiple alerts in <1 min. The `mode: single` already prevents this for the same automation, but if you have multiple alerts (free + taken + summary), they share rate limit.

#### Problem: Disk full

**Symptoms:** Frigate crashes, recordings missing.

```bash
docker exec frigate du -sh /media/frigate/*
```

**Fix:** Lower retention (section 15) + restart. Or expand host disk.

#### Problem: Camera unreachable after IP change

Reolink got a new IP from DHCP.

**Fix:** Set static IP in camera + router DHCP reservation. Edit `config/frigate.yml` line `CAMERA_IP_PLACEHOLDER` (already substituted by setup.sh) — find/replace.

---

## 17. FAQ

**Q: How fast is the alert?**
A: Detection ~200 ms + MQTT ~50 ms + HA 2-min wait + CallMeBot HTTP ~3 s = **~2:03** from car leaving to WhatsApp on phone. The 2-min wait is configurable.

**Q: Can I use a non-Reolink camera?**
A: Yes — any RTSP-capable camera works. Change the RTSP URL in `config/frigate.yml`. Common formats:
- Hikvision: `rtsp://USER:PASS@IP:554/Streaming/Channels/101`
- Dahua: `rtsp://USER:PASS@IP:554/cam/realmonitor?channel=1&subtype=0`
- Generic ONVIF: depends on camera

**Q: Does it work at night?**
A: Yes, if the camera has IR illumination (most Reolink models do). Performance depends on light quality.

**Q: Will I get an alert if someone steals my car?**
A: Yes — car leaves spot → alert. This isn't a theft-specific alert (it doesn't know "you didn't leave"). For theft detection use a separate motion + person detection automation in HA.

**Q: Can I add a CO2 sensor / smart lock / other integration?**
A: Yes — Home Assistant supports 1000+ integrations. Add normally via HA UI → Settings → Devices & Services.

**Q: Costs?**
A: **$0/month** for the stack. Optional: Coral USB TPU (~$60 one-time), Nabu Casa for remote HA (~$6.5/mo), donation to CallMeBot (voluntary).

**Q: What if CallMeBot shuts down?**
A: Fall back to Telegram (section 9), or Signal, or email, or HA Companion App push notifications. The architecture isolates notification from detection.

**Q: How accurate is YOLOv8 for cars?**
A: ~95-99% on clear daytime scenes, ~85-95% at night with IR, ~70-90% in heavy rain/snow.

**Q: Does it record evidence if my car is hit?**
A: Yes — Frigate records the main stream during events. Retrieve from `/media/frigate/recordings/` or Frigate UI → Recordings → search by time.

**Q: Can I view live feed remotely?**
A: Yes via HA Companion App (if you set up Nabu Casa or VPN). Or directly via Frigate's WebRTC stream if you expose port 8555.

**Q: How do I uninstall?**

```bash
cd parking-empty-alert
docker compose down -v        # stops containers + removes volumes
cd ..
rm -rf parking-empty-alert
```

This removes everything except saved recordings on the host disk (separate `docker volume rm` for that).

---

**More questions?** Open an issue: https://github.com/marczyn/parking-empty-alert/issues
