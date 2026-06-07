# 🟦 Synology DSM Deployment Guide

Deploy parking-empty-alert on a Synology NAS via **Container Manager** (DSM 7.2+) or **Docker** (DSM 7.1).

**Tested on:** DS220+, DS920+, DS923+, DS1522+, DS1821+
**Time:** 20-30 minutes

---

## Prerequisites

- Synology NAS with **DSM 7.2 or higher**
- **Container Manager** package installed (Package Center → Container Manager → Install)
  - For DSM 7.1 use the older "Docker" package instead
- **SSH enabled** (Control Panel → Terminal & SNMP → Enable SSH)
- **Admin account access**
- Camera and NAS on **same LAN**

### Hardware recommended

- DS920+, DS923+, DS1522+ or newer
- 4 GB RAM minimum (8 GB recommended)
- At least 30 GB free on volume1 (100 GB+ for 7-day recordings)
- Avoid: DS218, DS220j (ARM CPU, slow)

---

## Installation method choice

| Method | Pros | Cons |
|---|---|---|
| **A) SSH + docker compose** (recommended) | Full feature support including `network_mode: host`, healthchecks, depends_on conditions | Requires CLI comfort |
| **B) Container Manager UI** | No SSH, point-and-click | Some features (host network, healthchecks) need workarounds |

This guide covers both. **Method A is recommended** — it's just 3 commands once SSH is enabled.

---

## Method A: SSH + docker compose (recommended)

### Step 1 — Enable SSH

1. **Control Panel → Terminal & SNMP** → check **Enable SSH service**
2. Port: 22 (default) — or any unused port
3. **Apply**

### Step 2 — Create shared folder for the stack

1. **Control Panel → Shared Folder → Create**
2. Name: `docker`
3. Location: `volume1` (or your main pool)
4. Encryption: optional (uncheck for simplicity)
5. **Permissions:** your admin account → Read/Write
6. **Apply**

### Step 3 — SSH into NAS and clone repo

```bash
# From your computer (replace IP):
ssh admin@192.168.1.100

# On NAS:
cd /volume1/docker
sudo git clone https://github.com/marczyn/parking-empty-alert.git
cd parking-empty-alert
sudo chown -R admin:users .
```

### Step 4 — Run setup

```bash
bash scripts/setup.sh
```

Follow prompts as in main README. The script auto-detects Docker on Synology.

### Step 5 — Verify

```bash
sudo docker compose ps
```

Should show 3 healthy containers.

### Step 6 — Access UIs

- **Frigate:** `http://<nas-ip>:5000`
- **Home Assistant:** `http://<nas-ip>:8123`

If you see "port in use" errors, see [Port conflicts](#port-conflicts) below.

---

## Method B: Container Manager UI

### Step 1 — Create project folder

1. **File Station** → `volume1/docker` → **Create folder** → `parking-empty-alert`
2. Open **Container Manager** → **Project** → **Create**
3. **Project name:** `parking-empty-alert`
4. **Path:** Browse to `/volume1/docker/parking-empty-alert`
5. **Source:** Upload `docker-compose.yml` from this repo
6. (Also upload `config/` folder structure — File Station)

### Step 2 — Download stack files via File Station

In File Station, upload these files to `/volume1/docker/parking-empty-alert/`:

```
docker-compose.yml
docker-compose.macwin.yml  ← use this instead of host networking!
.env                       ← create with your secrets
config/
  ├── frigate.yml
  ├── mosquitto.conf
  └── homeassistant/
      ├── configuration.yaml
      ├── automations.yaml
      ├── secrets.yaml
      ├── scripts.yaml
      ├── scenes.yaml
      └── ui-lovelace.yaml
```

Easier: zip the repo on your computer, upload to NAS, extract via File Station.

### Step 3 — Set permissions

In File Station, right-click `parking-empty-alert` folder → Properties → Permissions:
- User `Container`: Read/Write
- Inherit to all sub-folders

### Step 4 — Create the project in Container Manager

1. **Container Manager → Project → Create**
2. Project name: `parking-empty-alert`
3. Path: `/volume1/docker/parking-empty-alert`
4. Source: **Create docker-compose.yml** (it auto-detects the file)
5. Combine compose files:
   - `docker-compose.yml`
   - `docker-compose.macwin.yml` (override for bridge network mode — required for UI deployment)
6. Click **Build**

### Step 5 — Start the project

Container Manager → Project → `parking-empty-alert` → **Action → Start**

All 3 containers should show **Running** status within ~2 minutes.

### Step 6 — Access UIs

Same URLs as Method A.

---

## Synology-specific considerations

### Port conflicts

DSM uses several ports by default. Likely conflicts:

| Port | Used by DSM for | Solution |
|---|---|---|
| **5000** | DSM HTTP (default) | Change Frigate port in docker-compose.yml: `"5001:5000"` |
| **5001** | DSM HTTPS (default) | Choose `5002` for Frigate |
| **8123** | None (Home Assistant default) | Usually OK |
| **1883** | None (MQTT default) | Usually OK |

To find what's using a port:
```bash
sudo netstat -tlnp | grep :5000
```

### Reverse proxy with HTTPS

Use DSM's built-in reverse proxy for clean URLs:

1. **Control Panel → Login Portal → Advanced → Reverse Proxy**
2. **Create:**
   - **Source:** `https://frigate.yourdomain.com` (or `frigate.<nas-hostname>.local`)
   - **Destination:** `http://localhost:5000`
   - Enable WebSocket
3. Repeat for HA: `https://ha.yourdomain.com` → `http://localhost:8123`
4. Use Let's Encrypt cert via Control Panel → Security → Certificate

### Storage paths

The stack uses Docker named volumes by default. To map them to a specific shared folder (easier backup):

Edit `docker-compose.yml`:
```yaml
services:
  frigate:
    volumes:
      - /volume1/docker/parking-empty-alert/storage:/media/frigate
      # ... rest
```

### Hardware acceleration

Synology models with Intel J4xxx or N5xxx CPUs have Intel iGPU — use `preset-vaapi` in `config/frigate.yml`:

```yaml
ffmpeg:
  hwaccel_args: preset-vaapi
```

**Verify VAAPI access from container:**
```bash
sudo docker exec frigate ls -la /dev/dri
# Should show renderD128 and card0
```

If missing, edit `docker-compose.yml` to expose the device:
```yaml
services:
  frigate:
    devices:
      - /dev/dri:/dev/dri
```

### Coral USB TPU

If you have a Coral USB TPU:

1. Plug into NAS USB port
2. Verify detection: `lsusb | grep -i google`
3. Edit `docker-compose.yml`:
   ```yaml
   services:
     frigate:
       devices:
         - /dev/bus/usb:/dev/bus/usb
   ```
4. Update Frigate config to use Coral detector (see main README)

### Auto-start on boot

Container Manager projects with `restart: always` auto-start. Verify:

1. **Container Manager → Project → `parking-empty-alert`**
2. Click **Settings** → check **Auto-restart**

For SSH-deployed stacks, `restart: always` in compose is enough — Docker daemon starts on boot, then containers.

### Backups

**Hyper Backup** (Synology's tool):
1. **Hyper Backup → Create Backup Task**
2. Local backup or remote (Synology C2, S3, B2, FTP)
3. Source: `/volume1/docker/parking-empty-alert/`
4. **Exclude:** `/volume1/docker/parking-empty-alert/storage/` (recordings are huge)
5. Schedule: Daily

**Snapshot Replication** (Btrfs only):
1. **Storage Manager → Snapshot Replication**
2. Create snapshot schedule for `/volume1/docker/parking-empty-alert/config`
3. Every 1 hour, retain 24 hours / 7 days / 4 weeks

### Resource monitoring

Container Manager → **Container** → click container name → **Details** → shows CPU/RAM/Disk/Network in real time.

For longer-term tracking, install **Container Manager → Logs** integration (DSM 7.2+).

---

## Troubleshooting

### Container Manager won't start the project

Check logs: **Container Manager → Project → `parking-empty-alert` → Logs**

Common causes:
- **Permission denied on config files:** Re-set folder permissions, user `Container` needs Read/Write
- **Port already in use:** See [Port conflicts](#port-conflicts)
- **Insufficient memory:** Check Resource Monitor; close other containers or add RAM

### Frigate has high CPU

- Verify VAAPI is enabled (above)
- Reduce sub-stream resolution in Reolink to 640×360 max
- Reduce `fps: 5` to `fps: 3` in `config/frigate.yml`
- Add Coral USB TPU

### Network mode "host" not available

Container Manager UI doesn't expose `network_mode: host`. Use `docker-compose.macwin.yml` override (Method B) or switch to Method A (SSH).

### Recordings filling up disk

```bash
sudo du -sh /volume1/docker/parking-empty-alert/storage/*
```

Reduce retention in `config/frigate.yml`:
```yaml
record:
  retain:
    days: 1     # was 3
```

### Home Assistant Companion can't find HA

In bridge mode, Companion App auto-discovery doesn't work. Manually configure URL:
- App settings → Add server → `http://<nas-ip>:8123`

### Docker daemon not starting after DSM update

Sometimes DSM updates break Container Manager. Fix:
1. **Package Center → Container Manager → Stop**
2. SSH: `sudo systemctl restart pkgctl-Docker.service`
3. **Package Center → Container Manager → Start**

---

## Synology-specific best practices

✅ Use a **dedicated shared folder** for the project (don't put in home directory)
✅ Use **CMR drives** for the storage volume — SMR drives slow under continuous writes
✅ Configure **Btrfs snapshots** of config — instant recovery
✅ Set up **Synology HyperBackup** to C2 or S3 for off-site backup of config
✅ Use **reverse proxy** for clean URLs + Let's Encrypt cert
✅ Monitor **disk health** via Storage Manager — recordings stress disks
✅ Enable **email notifications** for SMART alerts

❌ Don't use a `homes` folder for Docker volumes — slow + permission issues
❌ Don't store on USB-attached drives — unstable for 24/7
❌ Don't enable HDD hibernation — Frigate prevents spin-down anyway

---

## Reference

- Synology Container Manager docs: https://www.synology.com/en-global/dsm/feature/container-manager
- Frigate documentation: https://docs.frigate.video
- Main README: [../../README.md](../../README.md)
- Common issues: [docs/INSTALLATION.md §11](../INSTALLATION.md#11-common-installation-issues)
