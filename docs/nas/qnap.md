# 🟩 QNAP QTS Deployment Guide

Deploy parking-empty-alert on QNAP NAS using **Container Station** (QTS 5.x).

## Two paths

### 🅰️ Simple — pull pre-built AIO image (recommended)

1. Container Station → **Images** → **Pull**
2. **Registry:** Other → URL: `ghcr.io/marczyn/parking-empty-alert:latest` (full) or `ghcr.io/marczyn/parking-empty-alert-lite:latest` (no-HA)
3. **Images** → click pulled image → **Create**
4. **Port mapping:** `8090:8090`, plus `8123:8123` (full only) **or** `1883:1883` (lite only — full keeps MQTT in-container)
5. **Environment variables:** `FRIGATE_CAMERA_IP`, `FRIGATE_RTSP_USER`, `FRIGATE_RTSP_PASSWORD` (required); full → `WHATSAPP_PHONE` + `WHATSAPP_APIKEY` (required); lite → `FRIGATE_MQTT_USER` + `FRIGATE_MQTT_PASSWORD` (required, your external HA's broker login)
6. **Run** — done (the container fails fast if a required secret is missing).

Open `http://<qnap-ip>:8090` (Frigate) and `http://<qnap-ip>:8123` (HA, full only).

### 🅱️ Advanced — git clone + Container Station Application (covered below)

For multi-camera / LPR deployments.

**Tested on:** TS-453D, TS-464, TS-673A, TVS-672N
**Time:** 25-35 minutes

---

## Prerequisites

- QNAP NAS with **QTS 5.0 or higher**
- **Container Station 3.0+** installed (App Center → Container Station → Install)
- **SSH enabled** (Control Panel → Telnet/SSH → Allow SSH connection)
- **Admin account access**
- Camera and NAS on **same LAN**

### Hardware recommended

- Quad-core x86 CPU (Intel Celeron J4xxx, N5xxx, or AMD Ryzen)
- 4 GB RAM minimum (8 GB recommended)
- Avoid: TS-x32 (ARM models — limited Frigate support)

---

## Installation

### Step 1 — Enable SSH

1. **Control Panel → Network & File Services → Telnet/SSH**
2. **Allow SSH connection**, port 22 (or custom)
3. **Apply**

### Step 2 — Install Container Station

1. **App Center → All Apps → Container Station** → **Install**
2. After install, open Container Station → accept terms → wait for setup

### Step 3 — Create shared folder for Docker

1. **Control Panel → Privilege → Shared Folders → Create**
2. Folder name: `Container`
3. Disk volume: your main pool
4. Hide network drive: optional
5. **Permissions:** your admin user → Read/Write

### Step 4 — SSH into NAS and clone repo

```bash
# From your computer (replace IP):
ssh admin@<qnap-ip>

# On NAS:
cd /share/Container
mkdir parking-empty-alert
cd parking-empty-alert

# Clone the repo
git clone https://github.com/marczyn/parking-empty-alert.git .

# Or download ZIP if git not available:
# curl -L https://github.com/marczyn/parking-empty-alert/archive/refs/heads/main.tar.gz | tar xz --strip-components=1
```

### Step 5 — Run setup script

```bash
bash scripts/setup.sh
```

### Step 6 — Add to Container Station

#### Option A: Via SSH (recommended)

```bash
cd /share/Container/parking-empty-alert
docker compose up -d
```

Container Station picks up the running containers automatically.

#### Option B: Via Container Station UI

1. **Container Station → Create → Create Application**
2. **Application name:** `parking-empty-alert`
3. **Source:** Upload your YAML
4. Paste contents of `docker-compose.yml`
5. **Validate YAML** → fix any issues
6. **Create**

Note: QNAP Container Station has been known to misparse some valid compose YAML. Option A (SSH) is more reliable.

### Step 7 — Verify

```bash
docker compose ps
```

Should show 3 healthy containers.

### Step 8 — Access UIs

- **Frigate:** `http://<qnap-ip>:5000`
- **Home Assistant:** `http://<qnap-ip>:8123`

---

## QNAP-specific considerations

### Port conflicts

QTS uses several ports:

| Port | Used by | Solution |
|---|---|---|
| **5000** | Container Station (sometimes) | Change Frigate to `"5001:5000"` |
| **8080** | QuTS Hero or some apps | Usually not affected — but watch out |
| **80** | QTS HTTP | Use reverse proxy if needed |

Check ports in use:
```bash
netstat -tlnp | head -20
```

### Storage paths

QNAP convention: `/share/<volume>/<folder>/`

| Item | Location |
|---|---|
| Stack configs | `/share/Container/parking-empty-alert/config/` |
| Recordings | `/share/Container/parking-empty-alert/storage/` (or external array) |

Edit `docker-compose.yml` to bind to specific path:
```yaml
services:
  frigate:
    volumes:
      - /share/CACHEDEV1_DATA/Container/parking-empty-alert/storage:/media/frigate
```

### Hardware acceleration

#### Intel iGPU (vaapi)

QNAP models with Intel J/N-series CPUs expose `/dev/dri`. Verify:
```bash
ls -la /dev/dri/
```

Edit `docker-compose.yml`:
```yaml
services:
  frigate:
    devices:
      - /dev/dri:/dev/dri
```

In `config/frigate.yml`: uncomment `hwaccel_args: preset-vaapi`

Also in `docker-compose.yml`, uncomment the `devices: [/dev/dri:/dev/dri]` block under the `frigate` service. Restart: `docker compose up -d`.

#### Coral USB TPU

1. Plug into NAS USB port (QNAP TS models often have USB 3.0 + USB 2.0)
2. SSH: `lsusb | grep -i google`
3. Edit `docker-compose.yml`:
   ```yaml
   services:
     frigate:
       devices:
         - /dev/bus/usb:/dev/bus/usb
       privileged: true   # QNAP often needs this for USB device access
   ```

### Auto-start on boot

Container Station handles auto-restart if `restart: always` is in compose. Verify:

```bash
docker inspect frigate --format '{{.HostConfig.RestartPolicy.Name}}'
# Should output: always
```

If not:
```bash
docker update --restart=always frigate mosquitto homeassistant
```

### Reverse proxy

QNAP has **App Center → Application Servers → Web Server** but it's limited. Better: install **Nginx Proxy Manager** via Container Station:

```yaml
# nginx-proxy-manager.yml
services:
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    ports:
      - "81:81"      # admin UI
      - "443:443"
      - "80:80"
    volumes:
      - /share/Container/npm/data:/data
      - /share/Container/npm/letsencrypt:/etc/letsencrypt
```

Then in NPM admin UI (`http://<qnap>:81`):
- Add proxy host: `frigate.yourdomain.com` → `http://<qnap-ip>:5000`
- Add SSL via Let's Encrypt

### Backups via HBS3

QNAP Hybrid Backup Sync 3 (HBS3):
1. **HBS3 → Backup & Restore → Create Backup Job**
2. **Source:** `/share/Container/parking-empty-alert/config/`
3. **Destination:** another NAS, S3, B2, Google Drive
4. Schedule: nightly
5. **Exclude:** `storage/` (recordings)

### Storage tier (SSD vs HDD)

Many QNAP models support SSD caching:
- **Recommended:** put `config/` and small files on SSD cache
- Put `storage/` (recordings) on HDD array — too large for SSD

Configure via **Storage & Snapshots → Cache Acceleration**.

### Resource limits

Container Station doesn't have intuitive resource limit UI. Use SSH:
```bash
docker update --memory 1g --memory-swap 2g frigate
docker update --cpus 4 frigate
```

Or add to `docker-compose.yml`:
```yaml
services:
  frigate:
    mem_limit: 1g
    mem_reservation: 512m
    cpus: 4.0
```

### Notifications integration

QNAP's notification system can call shell scripts. Add WhatsApp notify:

```bash
# Create /share/Container/qnap-whatsapp.sh
cat > /share/Container/qnap-whatsapp.sh <<'EOF'
#!/bin/bash
MSG="$1"
curl "https://api.callmebot.com/whatsapp.php?phone=YOUR_PHONE&text=QNAP:%20$MSG&apikey=YOUR_KEY"
EOF
chmod +x /share/Container/qnap-whatsapp.sh
```

Configure in Control Panel → Notification → Custom email → Custom Script.

---

## Troubleshooting

### Container Station won't validate the YAML

Container Station's YAML validator is strict and sometimes wrong. Use SSH method instead:
```bash
cd /share/Container/parking-empty-alert
docker compose up -d
```

### Frigate has high CPU

Check VAAPI is exposed:
```bash
docker exec frigate ls /dev/dri
# Should show renderD128
```

If empty, add device to compose (above) and recreate container.

### Recordings cause disk fill warning

QTS warns at 80% disk usage. Reduce retention:
```yaml
record:
  retain:
    days: 1     # was 3
```

Or move to a larger volume:
```yaml
services:
  frigate:
    volumes:
      - /share/CACHEDEV2_DATA/Container/storage:/media/frigate
```

### Container Station updates break the stack

QNAP sometimes updates Container Station to a new major version that breaks compose features.

**Recovery:**
1. Backup config first
2. Update Container Station via App Center
3. SSH: `cd /share/Container/parking-empty-alert && docker compose down && docker compose up -d`
4. Reconfigure if any YAML field was deprecated

### USB device for Coral disappears after reboot

QNAP USB allocation is not persistent. Add to udev rules:
```bash
# /etc/udev/rules.d/99-coral.rules
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", ATTR{idProduct}=="9302", MODE="0666"
```

Reload: `sudo udevadm control --reload`

### MyQNAPCloud reverse proxy strips WebSocket

If using MyQNAPCloud for remote access:
- WebSockets needed for Frigate UI may not pass through
- Fix: use NPM (Nginx Proxy Manager) instead — supports WebSocket

---

## QNAP-specific best practices

✅ Use **SSH method** for deploying — Container Station UI has YAML quirks
✅ Put `storage/` (recordings) on **HDD volume**, not SSD cache
✅ Install **Nginx Proxy Manager** for HTTPS + clean URLs (not MyQNAPCloud)
✅ Use **HBS3** for nightly config backup to remote target
✅ Monitor via Container Station's per-container stats
✅ Verify VAAPI access — Intel CPU NAS get free hardware accel

❌ Avoid QNAP cloud notifications for security-critical alerts (MyQNAPCloud has SLA gaps)
❌ Don't use Container Station's auto-update — sometimes breaks running stacks
❌ Don't disable SSH — needed for compose-level operations

---

## Reference

- QNAP Container Station docs: https://www.qnap.com/en/software/container-station
- QNAP Forum: https://forum.qnap.com/
- Main README: [../../README.md](../../README.md)
