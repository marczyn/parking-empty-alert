# 🚀 Quick Start (12 minutes)

Minimum steps to get parking detection running.

For detailed setup with troubleshooting, see [INSTALLATION.md](INSTALLATION.md).

---

## Choose your scenario

The installer asks at startup whether you already have Home Assistant:

| Scenario | What runs | Manual HA setup needed? |
|---|---|---|
| **A) No existing HA** (default) | Frigate + Mosquitto + HA bundled | ❌ Auto-configured |
| **B) Already have HA in network** | Frigate + Mosquitto only | ✅ Add MQTT + Frigate integration to your HA |

---

## Prerequisites (2 min)

- Computer/server with **Docker** installed ([install guide](https://docs.docker.com/get-docker/))
- Reolink (or Hikvision/Dahua/UniFi/Tapo/ONVIF) camera on same LAN, with **static IP**
- Phone with **WhatsApp** installed

---

## Step 1 — Enable RTSP on camera (2 min)

In Reolink app or web UI:
1. **Settings → Network → Advanced → Port Settings** → enable **RTSP** (port 554)
2. **Settings → User → Add User** → username `frigate`, permission **Viewer**, save password

---

## Step 2 — Get CallMeBot WhatsApp APIKEY (3 min)

1. Add **+34 644 11 11 11** to phone contacts (call it "CallMeBot")
2. Open WhatsApp → CallMeBot → send: `I allow callmebot to send me messages`
3. Wait 1-2 min for reply with your APIKEY (7 digits)

---

## Step 3 — Pull + run all-in-one image (3 min)

**Pick image based on your scenario:**

| Scenario | Image |
|---|---|
| 🅰️ I don't have HA | `ghcr.io/marczyn/parking-empty-alert:latest` (full) |
| 🅱️ I have HA in my network | `ghcr.io/marczyn/parking-empty-alert-lite:latest` |

### 🅰️ FULL — Frigate + Mosquitto + HA in one container

```bash
docker run -d --name parking \
  -p 5000:5000 -p 8123:8123 -p 1883:1883 \
  -e CAMERA_IP=192.168.1.100 \
  -e FRIGATE_RTSP_USER=frigate \
  -e FRIGATE_RTSP_PASSWORD=yourpassword \
  -e WHATSAPP_PHONE=48501234567 \
  -e WHATSAPP_APIKEY=1234567 \
  ghcr.io/marczyn/parking-empty-alert:latest
```

After ~1 min boot:
- **Frigate UI:** http://localhost:5000
- **Home Assistant:** http://localhost:8123
- **MQTT broker:** localhost:1883

### 🅱️ LITE — Frigate + Mosquitto only (use your existing HA)

```bash
docker run -d --name parking-lite \
  -p 5000:5000 -p 1883:1883 \
  -e CAMERA_IP=192.168.1.100 \
  -e FRIGATE_RTSP_USER=frigate \
  -e FRIGATE_RTSP_PASSWORD=yourpassword \
  ghcr.io/marczyn/parking-empty-alert-lite:latest
```

After ~1 min boot:
- **Frigate UI:** http://localhost:5000
- **MQTT broker:** localhost:1883

In your existing HA, add:
- MQTT integration → broker: `<docker-host-ip>:1883`
- Frigate integration → URL: `http://<docker-host-ip>:5000`

### Works on

Linux • macOS Docker Desktop • Windows Docker Desktop • WSL2 • Synology Container Manager • UnRAID • QNAP

Multi-arch: `amd64` + `arm64` (auto-selected for your platform).

---

## Step 4 — Draw your parking zone (2 min)

1. Open **http://localhost:5000** → click camera **parking**
2. **Settings → Edit Zones** (top right)
3. Draw polygon around your parking spot
4. Save → copy coordinates from popup
5. Paste into `config/frigate.yml`:
   ```yaml
   zones:
     parking_spot:
       coordinates: <PASTE HERE>
   ```
6. `docker compose restart frigate`

---

## Done! Test it

Park a car in your spot → wait 30s → drive away.

After 2 minutes you'll receive WhatsApp:
> 🅿️ Parking spot FREE!

---

## Common issues

| Problem | Fix |
|---|---|
| "Stream offline" in Frigate | Wrong RTSP path — try `h265Preview_01_sub` if camera uses HEVC |
| No WhatsApp received | Run `curl "https://api.callmebot.com/whatsapp.php?phone=YOUR_PHONE&text=test&apikey=YOUR_KEY"` to test |
| HA Frigate integration "Cannot connect" | On Linux use `http://localhost:5000`, on Docker Desktop use `http://frigate:5000` |
| Port 5000 conflict (Synology) | Edit `docker-compose.yml`, change `"5000:5000"` → `"5001:5000"` |

For more, see [INSTALLATION.md](INSTALLATION.md#11-common-installation-issues).

---

## Next steps

- **Tune detection** — see [User Guide → Tuning detection](USER_GUIDE.md#5-tuning-detection)
- **Multi-camera setup** — see [examples/multi-camera/](../examples/multi-camera/README.md)
- **Use Telegram instead of WhatsApp** — see [examples/telegram/](../examples/telegram/README.md)
- **Already use Synology Surveillance Station?** — see [Synology Surveillance Station guide](synology-surveillance-station.md)
- **Deploy on NAS** — see [NAS guides](nas/README.md) for Synology/UnRAID/QNAP
