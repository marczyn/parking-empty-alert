# Installation Guide

This is the **detailed** installation guide. For a quick 3-line start see [README](../README.md).

**Estimated time:** 45-60 minutes (first time, no prior Docker experience).

---

## Table of contents

1. [Prerequisites](#1-prerequisites)
2. [Install Docker](#2-install-docker)
3. [Prepare the Reolink camera](#3-prepare-the-reolink-camera)
4. [Set up CallMeBot WhatsApp](#4-set-up-callmebot-whatsapp)
5. [Clone the repository](#5-clone-the-repository)
6. [Run the setup script](#6-run-the-setup-script)
7. [Verify each service is healthy](#7-verify-each-service-is-healthy)
8. [Draw the parking zone in Frigate UI](#8-draw-the-parking-zone-in-frigate-ui)
9. [Add Frigate integration in Home Assistant](#9-add-frigate-integration-in-home-assistant)
10. [End-to-end test](#10-end-to-end-test)
11. [Common installation issues](#11-common-installation-issues)

---

## 1. Prerequisites

### Hardware

A computer/server that will run 24/7 — anything from a low-end mini-PC to a NAS or repurposed laptop works.

| Component | Minimum | Recommended |
|---|---|---|
| CPU | Dual-core 1.5 GHz (Intel Celeron, AMD GX, ARM Cortex-A72) | Quad-core 2 GHz+ (Intel N100, i3, AMD Ryzen) |
| RAM | 2 GB free | 4 GB free |
| Disk | 30 GB free SSD/HDD | 100 GB SSD (for longer video retention) |
| Network | 100 Mbps Ethernet to camera | 1 Gbps Ethernet |
| Power | Stable mains | Mains + UPS (~30 min battery) |

### Operating System

Any of these works:
- **Linux** (any modern distro: Ubuntu 22.04+, Debian 12+, Fedora 39+, Arch, etc.)
- **Windows** 10/11 (with Docker Desktop)
- **macOS** 13+ (with Docker Desktop)

Linux is recommended for production (lower resource overhead, better stability for 24/7).

### Network

- The Docker host **must be on the same LAN** as the Reolink camera (same VLAN/subnet, or routing between them)
- The Docker host needs **internet access** (to pull Docker images + send WhatsApp via CallMeBot)
- The Reolink camera should have a **static IP** (set in router DHCP reservations) — if its IP changes, Frigate will fail to connect

### Reolink camera

- Any model: RLC-810A, RLC-820A, Duo 2, TrackMix, Argus 3, E1 Outdoor, NVR with cameras attached, etc.
- Firmware up to date (check Reolink app → Device → Firmware)
- Camera positioned with **clear view of the parking spot** (top-front angle is best)

### Phone

- Android or iOS with **WhatsApp installed and active**
- Phone number must be reachable on WhatsApp (you'll add CallMeBot as a contact)

---

## 2. Install Docker

Skip this step if you already have Docker installed (`docker --version` works).

### Linux (Ubuntu/Debian)

```bash
# Install Docker Engine (from official repository)
curl -fsSL https://get.docker.com | sudo sh

# Add yourself to docker group (so you can run docker without sudo)
sudo usermod -aG docker $USER

# Log out and back in for group membership to take effect
# Verify
docker --version
docker compose version
```

Expected output:
```
Docker version 28.x.x, build ...
Docker Compose version v2.x.x
```

### Windows

1. Download **Docker Desktop**: https://www.docker.com/products/docker-desktop/
2. Run installer, accept defaults
3. After install, Docker Desktop starts automatically
4. Open PowerShell or Terminal and verify:
   ```powershell
   docker --version
   docker compose version
   ```

### macOS

1. Download **Docker Desktop**: https://www.docker.com/products/docker-desktop/
2. Drag Docker.app to Applications
3. Launch Docker Desktop, wait for green status indicator
4. Open Terminal and verify:
   ```bash
   docker --version
   docker compose version
   ```

### Verify Docker can pull images

```bash
docker run --rm hello-world
```

Should print "Hello from Docker!". If you see permission errors on Linux, you forgot to log out/in after `usermod`.

---

## 3. Prepare the Reolink camera

### 3.1 Find the camera IP address

**Option A:** Reolink mobile app → Device → Device Info → IP address

**Option B:** Router DHCP clients list (look for "Reolink-*" or MAC starting with `f8:01:b4`)

**Option C:** Network scan from Docker host:
```bash
# Linux/macOS:
nmap -sn 192.168.1.0/24 | grep -B 2 -i reolink

# Windows PowerShell:
arp -a | findstr "f8-01-b4"
```

**Recommended:** Make the camera IP **static**:
- Reolink web UI (open `http://<camera_ip>` in browser) → Settings → Network → DHCP off → set IP/Subnet/Gateway
- **OR** Router DHCP reservation by camera MAC address

### 3.2 Enable RTSP

In Reolink mobile app **or** camera web UI:

1. Open **Settings → Network → Advanced → Port Settings**
2. Find **RTSP** row, toggle **Enable**
3. Port stays at **554** (default)
4. **Save**

### 3.3 Create a dedicated Frigate user

Best practice: don't reuse your admin account.

1. **Settings → User → Add User**
2. Fields:
   - Username: `frigate`
   - Permission: **Viewer** (read-only)
   - Password: generate a strong one and save it
3. **Save**

### 3.4 Configure stream profiles

Frigate uses 2 streams from the camera:
- **Sub stream** (low-res) for AI detection — lower CPU/network usage
- **Main stream** (high-res) for video recording

1. **Settings → Display → Stream**
2. Configure **Main Stream**:
   - Resolution: `1920 × 1080` (or maximum available)
   - Frame rate: `25` fps
   - Encoding: `H.264` (preferred — wider compatibility) or H.265
   - Bit rate: `2048 Kbps` (or default)
3. Configure **Sub Stream**:
   - Resolution: `640 × 360` (or `640 × 480`)
   - Frame rate: `5` fps (low — Frigate only needs 5fps for detection)
   - Encoding: `H.264`
   - Bit rate: `512 Kbps`
4. **Save**

### 3.5 Test RTSP from Docker host

Before continuing, verify the RTSP stream is reachable:

```bash
# Replace USER, PASS, IP with your values
docker run --rm linuxserver/ffmpeg:latest \
  -rtsp_transport tcp \
  -i "rtsp://frigate:PASS@192.168.1.100:554/h264Preview_01_sub" \
  -frames:v 1 -f null - 2>&1 | grep "Stream #"
```

Expected output:
```
Stream #0:0: Video: h264 (Constrained Baseline), yuv420p, 640x360, 5 fps...
```

If you see "Connection refused" or "401 Unauthorized" — fix the camera config before continuing.

---

## 4. Set up CallMeBot WhatsApp

**CallMeBot** is a free service (no fees, no registration) that sends WhatsApp messages via HTTP API.

### 4.1 Add CallMeBot to your contacts

1. Open your phone's contact app
2. **Add new contact:**
   - Name: `CallMeBot`
   - Phone number: `+34 644 11 11 11`
3. Save

### 4.2 Authorize CallMeBot

1. Open WhatsApp
2. Start a new chat → search for `CallMeBot`
3. Send exactly this message:
   ```
   I allow callmebot to send me messages
   ```
4. Wait 1-2 minutes (sometimes up to 5 min during high load)
5. You'll receive a reply like:
   ```
   API Activated for your phone number.
   Your APIKEY is 1234567
   To get help on the API visit: https://www.callmebot.com/blog/free-api-whatsapp-messages/
   ```
6. **Write down the APIKEY** (7 digits)

### 4.3 Manual test (optional but recommended)

In a terminal on any machine with internet access:

```bash
curl "https://api.callmebot.com/whatsapp.php?phone=48501234567&text=test&apikey=1234567"
```

Replace `48501234567` with your phone (international format, no `+`).

You should receive "test" on WhatsApp within 30 seconds.

### CallMeBot rate limits

- 1 message per minute per phone number
- Free tier — no SLA, but reliable in practice (>99% delivery)
- Donations welcome on https://www.callmebot.com/ (recommended if you use it heavily)

---

## 5. Clone the repository

On the Docker host:

```bash
cd ~  # or wherever you want it
git clone https://github.com/marczyn/parking-empty-alert.git
cd parking-empty-alert
ls -la
```

You should see:
```
docker-compose.yml
.env.example
README.md
LICENSE
.gitignore
config/
scripts/
examples/
docs/
.github/
```

### If you don't have git

Download the ZIP archive:
```bash
# Linux/macOS:
curl -L https://github.com/marczyn/parking-empty-alert/archive/refs/heads/main.tar.gz | tar xz
cd parking-empty-alert-main

# Windows: download the ZIP from
# https://github.com/marczyn/parking-empty-alert/archive/refs/heads/main.zip
# extract and open in PowerShell
```

---

## 6. Run the setup script

```bash
bash scripts/setup.sh
```

The script asks 6 questions:

| Question | Example answer |
|---|---|
| Reolink camera IP | `192.168.1.100` |
| Reolink username | `frigate` |
| Password for this account | `<the one you set in step 3.3>` |
| Phone number (NO +, just digits) | `48501234567` |
| CallMeBot APIKEY | `1234567` |

The script then:

1. ✓ Checks Docker is installed
2. ✓ Creates `.env` with your config + a randomly generated MQTT password
3. ✓ Updates `config/homeassistant/secrets.yaml`
4. ✓ Substitutes `CAMERA_IP_PLACEHOLDER` in `config/frigate.yml`
5. ✓ Generates Mosquitto password file
6. ✓ Tests RTSP to camera (warns if no stream)
7. ✓ Sends WhatsApp test message (you should receive it!)
8. ✓ Runs `docker compose up -d`

Expected final output:
```
════════════════════════════════════════════════════
✅ DONE!
════════════════════════════════════════════════════

  Frigate UI:        http://localhost:5000
  Home Assistant:    http://localhost:8123
```

Check phone — you should have received a WhatsApp message:
> parking-pack setup test — if you see this message, alerts work!

If you didn't receive the test message — check CallMeBot reply for APIKEY, verify phone format.

---

## 7. Verify each service is healthy

### 7.1 Check containers are running

```bash
docker compose ps
```

Expected:
```
NAME              IMAGE                                  STATUS
frigate           ghcr.io/blakeblackshear/frigate        Up X minutes (healthy)
homeassistant     ghcr.io/home-assistant/home-assistant  Up X minutes
mosquitto         eclipse-mosquitto:2.0                  Up X minutes
```

All 3 should be `Up`. If any shows `Restarting` or `Exited`, check logs:

```bash
docker compose logs frigate | tail -50
docker compose logs homeassistant | tail -50
docker compose logs mosquitto | tail -20
```

### 7.2 Check Mosquitto (MQTT broker)

```bash
docker exec mosquitto mosquitto_sub \
  -h localhost \
  -u frigate \
  -P "$(grep MQTT_PASSWORD .env | cut -d= -f2)" \
  -t 'frigate/#' \
  -C 1 -W 5
```

If output shows JSON-like data, MQTT is working. If "Connection refused" — Mosquitto config issue.

### 7.3 Check Frigate UI

Open `http://<your-docker-host-IP>:5000` in browser.

You should see:
- **Top bar:** "Frigate" logo
- **Left sidebar:** Live, Events, Recordings, Debug, etc.
- **Cameras list:** `parking` (your camera)

Click on `parking` — you should see the live feed. If it's a black/grey screen with "Stream offline" — the RTSP path is wrong. See [Common installation issues](#11-common-installation-issues).

**Note: AI model download on first run**

On first Frigate startup, the YOLOv8 detection model (~50 MB) downloads automatically from the Frigate model registry. This requires **internet access** during initial setup.

- ✅ With internet: model downloads in ~30 seconds; Frigate starts AI detection
- ❌ Air-gapped network: model download fails, Frigate runs but detection is broken

If running in an isolated network, see the [Frigate model docs](https://docs.frigate.video/configuration/object_detectors/#downloading-models) for manual model placement in `model_cache/`.

### 7.4 Check Home Assistant

Open `http://<your-docker-host-IP>:8123`.

First time you'll see the onboarding wizard:
1. **Create your account** (admin login + password)
2. **Set location** (city, time zone, currency — choose your country)
3. **Choose units** (metric for most countries)
4. Click "Finish"

You should see the default HA dashboard.

---

## 8. Draw the parking zone in Frigate UI

This is the **most important** step — Frigate needs to know **exactly where** the parking spot is in the camera frame.

### 8.1 Open zone editor

In Frigate 0.13+:

1. Frigate UI → click camera **parking**
2. Click **Configuration** (top-right gear icon) — or **Settings** in some themes
3. Look for **Edit Zones** button (right side panel)

For older Frigate versions or alternative path:
1. Frigate UI → click camera **parking**
2. Click **Debug** in the left menu
3. Click ⚙ **Settings** (top-right) → **Edit Zones**

You see live camera feed with optional overlays:
- **Bounding boxes** (white) — Frigate's object detections
- **Zones** (green) — your defined zones
- **Motion** (red boxes) — detected motion areas

### 8.2 Draw the zone polygon
3. **Click and drag** to draw points around the parking spot:
   - 4 points minimum (rectangle)
   - 6-8 points for irregular spots (recommended)
   - Cover the asphalt where the car wheels and body will be
   - **Don't include** sidewalk, street, or adjacent spots
4. When you're done, click **Save**
5. A popup shows the coordinates string. **Copy it!**

Example:
```
0.32,0.48,0.71,0.45,0.74,0.83,0.30,0.85
```

### 8.3 Paste coordinates into config

Open `config/frigate.yml` in a text editor:

```bash
nano config/frigate.yml
```

Find this section:
```yaml
zones:
  parking_spot:
    coordinates: 0.35,0.50,0.65,0.50,0.65,0.85,0.35,0.85   # PLACEHOLDER
    inertia: 3
```

Replace the `coordinates:` value with **your** copied string:
```yaml
zones:
  parking_spot:
    coordinates: 0.32,0.48,0.71,0.45,0.74,0.83,0.30,0.85
    inertia: 3
```

Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X` in nano).

### 8.4 Restart Frigate

```bash
docker compose restart frigate
```

Wait ~10 seconds, refresh Frigate UI → Debug view → you should see the **green zone polygon** overlayed on your camera feed.

---

## 9. Add Frigate integration in Home Assistant

### 9.1 Add integration

1. Open HA: `http://<your-docker-host-IP>:8123`
2. Login with your admin account
3. **Settings → Devices & Services → + Add Integration**
4. Search for `Frigate`
5. Click **Frigate**
6. **Configure URL** — ⚠️ **depends on Docker mode:**

   | Compose mode | HA network | URL to enter |
   |---|---|---|
   | Linux (default `docker-compose.yml`) | `host` | `http://localhost:5000` |
   | Docker Desktop (`+ docker-compose.macwin.yml`) | `bridge` | `http://frigate:5000` |

7. Leave other options default
8. **Submit**

HA discovers the camera, zone, all entities. ~10 new entities appear.

### 9.2 Verify entities exist

**Developer Tools → States** (`/developer-tools/state`).

In the search box type `parking`. You should see:

| Entity ID | State |
|---|---|
| `sensor.parking_parking_spot_car` | 0 or 1 (current car count) |
| `sensor.parking_parking_spot_active_objects` | 0 or 1 |
| `binary_sensor.parking_motion` | on/off |
| `binary_sensor.parking_person_occupied` | off (no person) |
| `binary_sensor.parking_car_occupied` | on/off |
| `camera.parking` | streaming |
| `image.parking_parking_spot` | snapshot |
| `switch.parking_detect` | on |
| `switch.parking_recordings` | on |

### 9.3 Reload automations

The WhatsApp `notify.whatsapp_parking` service is already configured by `setup.sh`. Reload to make sure:

1. **Developer Tools → YAML** (`/developer-tools/yaml`)
2. Click **Reload Notify Services**
3. Click **Reload Automations**

### 9.4 Verify WhatsApp service exists

**Developer Tools → Services** (`/developer-tools/service`).

In the dropdown type `notify.whatsapp`. You should see `notify.whatsapp_parking`. Click it, then:

- Service data:
  ```yaml
  message: "🅿️ HA test — if you see this, alerts work end-to-end!"
  ```
- Click **CALL SERVICE**

You should receive the message on WhatsApp.

---

## 10. End-to-end test

This validates the entire chain: camera → Frigate → MQTT → HA → WhatsApp.

### 10.1 Park a car in the spot

Watch Frigate UI → Debug — you should see a bounding box around the car, and the zone overlay should turn from green (empty) to **filled green** (car inside).

Wait ~10 seconds for Frigate to consider the car "stationary".

### 10.2 Check HA state changed

**Developer Tools → States** → `sensor.parking_parking_spot_car`

Value should be `1` (or higher if there are multiple objects detected as cars).

### 10.3 Drive the car away

Drive the car out of the spot.

After ~5-10 seconds Frigate should drop the car count to `0`.

### 10.4 Wait for the alert

The automation waits **2 minutes** of continuous "empty" state before sending. This filters out:
- Cars driving through quickly
- Brief detection flickers

After 2 minutes you should receive a WhatsApp:
> 🅿️ Parking spot FREE!
> You can park — became free 2 min ago.
> Time: 14:32

### 10.5 If something didn't work

See [Common installation issues](#11-common-installation-issues) below + the [User Guide troubleshooting section](USER_GUIDE.md#troubleshooting).

---

## 11. Common installation issues

### ❌ Frigate logs: `ffmpeg: Connection refused`

**Cause:** RTSP URL is wrong, or camera credentials don't match.

**Fix:**
1. Run RTSP test from step 3.5
2. If `Connection refused` — RTSP not enabled or wrong port
3. If `401 Unauthorized` — wrong username/password
4. If "Stream #0:0: Video: hevc" — your camera uses H.265 (HEVC). Edit `config/frigate.yml`:
   - Comment out the `h264Preview_01_sub` lines
   - Uncomment the `h265Preview_01_sub` lines

### ❌ Frigate UI shows "Stream offline"

**Cause:** Same as above, OR camera firewalled.

**Fix:**
```bash
# From Docker host
docker exec frigate ping -c 3 <camera_ip>
docker exec frigate nc -zv <camera_ip> 554
```

Both should succeed. If ping fails — network issue between container and camera.

### ❌ HA: Frigate integration "Cannot connect"

**Cause:** HA can't reach Frigate.

**Fix:** Check which HA network mode you're using:
- **Linux host mode (default):** use `http://localhost:5000` — HA shares host's network
- **Docker Desktop / bridge mode:** use `http://frigate:5000` — Docker DNS resolves between containers in same compose project

### ❌ WhatsApp test fails: "APIKEY invalid"

**Cause:** APIKEY entered with typo, or CallMeBot didn't activate yet.

**Fix:**
1. Re-send `I allow callmebot to send me messages` to CallMeBot
2. Wait 5 min, check WhatsApp for new APIKEY
3. Update `.env` and `config/homeassistant/secrets.yaml` with correct key
4. Restart HA: `docker compose restart homeassistant`

### ❌ MQTT auth fails

**Cause:** `config/passwd` not regenerated after editing.

**Fix:**
```bash
docker run --rm -v "$PWD/config:/mosquitto/config" eclipse-mosquitto:2.0 \
  mosquitto_passwd -c -b /mosquitto/config/passwd frigate "$(grep MQTT_PASSWORD .env | cut -d= -f2)"
docker compose restart mosquitto frigate homeassistant
```

### ❌ `sensor.parking_parking_spot_car` is always 0

**Cause:** Zone polygon doesn't cover where the car actually appears.

**Fix:** Frigate UI → Debug → enable "Bounding boxes" overlay. Park a car. You'll see Frigate's detection box. Compare with zone polygon. Redraw zone if needed.

### ❌ `sensor.parking_parking_spot_car` is `0` even when car is parked

**Cause:** Car is too small in frame (<1500 pixels²) or YOLO confidence too low.

**Fix:** Edit `config/frigate.yml`:
```yaml
objects:
  filters:
    car:
      min_area: 500       # was 1500 — try lower
      min_score: 0.3      # was 0.5 — try lower
```

### ❌ Stack doesn't survive reboot

**Cause:** Docker daemon not enabled at boot.

**Fix (Linux):**
```bash
sudo systemctl enable docker
```

---

## Next steps

After successful installation:

- 📖 Read the [User Guide](USER_GUIDE.md) for daily operation, advanced features, and tuning
- 🎨 Customize WhatsApp message text in `config/homeassistant/automations.yaml`
- ⚙ Adjust detection sensitivity (see User Guide → Tuning)
- 📷 Add a 2nd camera using `examples/multi-camera/`

---

**Need help?** Open an issue: https://github.com/marczyn/parking-empty-alert/issues
