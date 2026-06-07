# 🟧 UnRAID Deployment Guide

Deploy parking-empty-alert on UnRAID 6.12+ using **Compose Manager** plugin and **Community Apps**.

**Tested on:** UnRAID 6.12.x, 7.0 beta
**Time:** 15-25 minutes

---

## Prerequisites

- UnRAID **6.12 or higher** (recommended 7.0+ for native compose support)
- **Community Applications** plugin installed
- **Compose Manager** plugin installed (from Community Apps)
- **License:** any tier (Basic, Plus, Pro) — the project doesn't require Pro features
- Camera and UnRAID on **same LAN**

### Hardware

UnRAID's flexibility means anything x86 with 8GB+ RAM works. Recommended:
- Quad-core Intel or AMD CPU (last 5 years)
- 8 GB+ RAM
- Dedicated SSD cache for appdata (NVMe preferred)
- Array drives for recordings (CMR HDDs only)

---

## Installation

### Step 1 — Install Compose Manager plugin

1. **Apps tab** (Community Apps) → search **"Compose Manager"** by Squidly271
2. **Install** → wait for completion
3. After install, you have **Settings → Docker → Compose Manager** menu

### Step 2 — Create app directory

```bash
# SSH into UnRAID (Settings → SSH if not enabled):
ssh root@<unraid-ip>

# Create appdata folder
mkdir -p /mnt/user/appdata/parking-empty-alert
cd /mnt/user/appdata/parking-empty-alert

# Clone the repo
git clone https://github.com/marczyn/parking-empty-alert.git .
```

If git is not available, install via Community Apps "NerdTools" or download ZIP:
```bash
curl -L https://github.com/marczyn/parking-empty-alert/archive/refs/heads/main.tar.gz | \
  tar xz --strip-components=1
```

### Step 3 — Run setup script

```bash
cd /mnt/user/appdata/parking-empty-alert
bash scripts/setup.sh
```

Setup will ask for camera IP, RTSP credentials, CallMeBot APIKEY.

### Step 4 — Add to Compose Manager

1. **Settings → Docker → Compose Manager → ADD NEW STACK**
2. **Stack Name:** `parking-empty-alert`
3. **Path:** `/mnt/user/appdata/parking-empty-alert`
4. **Compose File:** `docker-compose.yml` (auto-detected)
5. **Save**

### Step 5 — Start the stack

In Compose Manager:
1. Find `parking-empty-alert` row
2. Click **▶ Compose Up**
3. Wait ~2 min for first start (image pulls)

### Step 6 — Verify

```bash
docker compose -f /mnt/user/appdata/parking-empty-alert/docker-compose.yml ps
```

Should show 3 healthy containers.

### Step 7 — Access UIs

- **Frigate:** `http://<unraid-ip>:5000`
- **Home Assistant:** `http://<unraid-ip>:8123`

---

## UnRAID-specific considerations

### Network mode "host" works perfectly

Unlike Synology, UnRAID Docker fully supports `network_mode: host`. No override needed — the main `docker-compose.yml` works as-is.

### Storage locations

| Path | What | Type |
|---|---|---|
| `/mnt/user/appdata/parking-empty-alert/` | Stack configs + scripts | Cache pool (SSD) |
| `/mnt/user/appdata/parking-empty-alert/storage/` | Frigate recordings | Cache then mover → Array |

**Recommended:** put `appdata/parking-empty-alert/storage` on the **array** (HDDs), not cache. Recordings are large + cache writes wear SSD.

Edit `docker-compose.yml`:
```yaml
services:
  frigate:
    volumes:
      - /mnt/user/parking-recordings:/media/frigate   # on array
      # other volumes...
```

### Hardware acceleration

#### Intel iGPU (vaapi)

UnRAID exposes `/dev/dri` by default. Just leave `hwaccel_args: preset-vaapi` in `config/frigate.yml`.

If multiple containers use `/dev/dri` (e.g., Plex transcoding + Frigate), UnRAID handles it without conflicts.

#### NVIDIA GPU

UnRAID has dedicated **NVIDIA-Driver** plugin (Community Apps):
1. Install plugin
2. Reboot
3. Edit `docker-compose.yml`:
   ```yaml
   services:
     frigate:
       runtime: nvidia
       deploy:
         resources:
           reservations:
             devices:
               - driver: nvidia
                 count: 1
                 capabilities: [gpu]
   ```
4. In `config/frigate.yml`: `hwaccel_args: preset-nvidia`

#### Coral USB TPU

1. Plug into UnRAID USB port
2. SSH: `lsusb | grep Google` — should show "Google Inc."
3. Edit `docker-compose.yml`:
   ```yaml
   services:
     frigate:
       devices:
         - /dev/bus/usb:/dev/bus/usb
   ```
4. Config Frigate to use edgetpu detector (see main README)

### Auto-start on boot

Compose Manager handles auto-start:
1. **Settings → Docker → Compose Manager**
2. Find `parking-empty-alert` → toggle **Autostart** ON

UnRAID starts Docker daemon at boot, then Compose Manager starts each stack with `restart: always`.

### Notifications integration

UnRAID can send its own notifications for stack issues. Integrate with the same WhatsApp:

1. **Settings → Notification Settings**
2. **Custom (User Script):**
   ```bash
   curl "https://api.callmebot.com/whatsapp.php?phone=$WHATSAPP_PHONE&text=UnRAID:%20$1&apikey=$WHATSAPP_APIKEY"
   ```
3. Trigger on: array errors, parity check failures, container restarts

### Backups via UnRAID's tools

**Method 1 — CA Backup/Restore Appdata** (recommended):
1. Install **CA Backup/Restore Appdata** plugin
2. Schedule weekly backup of `/mnt/user/appdata/parking-empty-alert/`
3. **Exclude:** `storage/` subdirectory (recordings are huge)
4. Backup target: secondary array, USB drive, or remote (rsync/SSH)

**Method 2 — Snapshots (ZFS):**
If your appdata is on ZFS:
```bash
zfs snapshot cache/appdata/parking-empty-alert@$(date +%Y%m%d)
```

Schedule via Plugin → User Scripts → cron.

### Reverse proxy + HTTPS

UnRAID's most popular reverse proxy: **SWAG** (Secure Web Application Gateway) from linuxserver.io.

1. Install **SWAG** from Community Apps
2. Configure domain + Let's Encrypt
3. Add proxy confs:
   ```
   /mnt/user/appdata/swag/nginx/proxy-confs/frigate.subdomain.conf.sample
   /mnt/user/appdata/swag/nginx/proxy-confs/ha.subdomain.conf.sample
   ```
   Rename `.sample` to `.conf`. Edit to point to `frigate:5000` / `homeassistant:8123`.

4. Access via `https://frigate.yourdomain.com`, `https://ha.yourdomain.com`

### Monitoring

UnRAID Dashboard shows Docker container CPU/RAM. For more detail:
- **Grafana + Prometheus** via Community Apps (advanced)
- **Netdata** plugin — instant per-container metrics

### Cache vs Array drive considerations

**Frigate writes a LOT.** Per camera at 5fps motion recording, expect:
- ~100 MB/hour to disk (1080p, motion-only)
- ~2 GB/day per camera (continuous motion areas)

On SSD cache, this wears the SSD. Move `storage/` to Array (HDD) using the array mover.

In UnRAID, edit Share Settings for `parking-empty-alert`:
- **Use cache pool:** No (write directly to array)
- Or: **Use cache pool:** Yes (mover to array daily)

### Resource limits

UnRAID Docker allows per-container limits. Right-click container in Docker tab → Edit:
- **Memory:** 1G for Frigate, 1G for HA, 256M for Mosquitto
- **CPU:** 4 cores for Frigate, all cores for HA

This prevents Frigate from starving other containers (Plex, Sonarr, etc.).

---

## Troubleshooting

### Compose Manager won't start the stack

Check Compose Manager logs (in plugin UI). Common causes:
- Port already in use (5000 is sometimes used by other UnRAID dockers)
- Insufficient permissions on appdata folder
- Out of memory (`docker stats`)

### Frigate logs show "Failed to allocate buffer"

UnRAID's tmpfs may be limited. Increase shm_size in `docker-compose.yml`:
```yaml
services:
  frigate:
    shm_size: 512mb
```

### Mover takes very long after recording day

Mover moves cache files to array nightly. For Frigate (writing constantly):
- Pause Frigate during mover: schedule via User Scripts
- Or: write recordings directly to array (slower but no mover)

### NVIDIA Driver plugin breaks after UnRAID update

UnRAID updates often require NVIDIA driver plugin reinstall:
1. Tools → Update OS
2. Wait for reboot
3. NVIDIA Driver plugin → reinstall matching kernel version
4. Reboot again

### Compose Manager doesn't update images

Force pull:
```bash
cd /mnt/user/appdata/parking-empty-alert
docker compose pull
docker compose up -d
```

### Trial license expired

Compose Manager works in Trial mode but UnRAID array won't mount after trial expires. **Purchase a license** (one-time fee, $60-130).

---

## UnRAID-specific best practices

✅ Put `storage/` (recordings) on the **array**, not cache (recordings are large)
✅ Put `config/` on the **cache pool** (SSD) for fast access
✅ Enable **CA Auto Update** for Community Apps to receive plugin updates
✅ Use **CA Backup/Restore Appdata** plugin for nightly config backups
✅ Install **NVIDIA-Driver** plugin if you have NVIDIA GPU
✅ Install **SWAG** for reverse proxy + HTTPS
✅ Monitor via UnRAID Dashboard + optional Netdata plugin

❌ Don't store recordings on cache only — fills SSD fast
❌ Don't run multiple Frigate instances on same array — write contention
❌ Don't use array drives less than 4TB — fills too quickly

---

## Reference

- UnRAID Forum: https://forums.unraid.net/
- Compose Manager docs: https://forums.unraid.net/topic/114415-plugin-compose-manager/
- Community Apps: https://forums.unraid.net/topic/38582-plug-in-community-applications/
- Main README: [../../README.md](../../README.md)
