# 📦 NAS Deployment Guides

Run the parking-empty-alert stack on a Network Attached Storage (NAS) device — no separate Docker host required.

## Simplest path — pre-built AIO image (any NAS)

If your NAS has Docker support (Container Manager / Compose Manager / Container Station), pull the all-in-one image:

```
ghcr.io/marczyn/parking-empty-alert:latest         # full (Frigate + Mosquitto + HA)
ghcr.io/marczyn/parking-empty-alert-lite:latest    # lite (Frigate + Mosquitto, for existing HA)
```

Set 5 environment variables, map 3 ports, run. **No git clone, no setup.sh, no Docker Compose knowledge required.**

Detailed steps in each NAS guide below.

## Why deploy on a NAS?

- ✅ **Already running 24/7** — no extra power consumption for a dedicated PC
- ✅ **Centralized storage** — recordings on the same disk as your other files
- ✅ **Built-in UPS support** — most NAS have battery backup
- ✅ **Container manager UI** — no SSH/CLI needed
- ✅ **Auto-start on boot** — survives power cuts
- ✅ **Built-in backup tools** — snapshots, replication, cloud sync

## Choose your NAS

| NAS | Guide | Pros | Cons |
|---|---|---|---|
| **[Synology](synology.md)** | DSM 7.2+ Container Manager | Best UI, Reverse Proxy built-in, mature ecosystem | Limited CPU on entry models (DS220+, DS218) |
| **[UnRAID](unraid.md)** | 6.12+ with Community Apps | Most flexible, GPU passthrough easy, huge plugin community | Paid license (~$60-130 one-time) |
| **[QNAP](qnap.md)** | QTS 5.x Container Station | Affordable, good hardware specs | Container Station UI less polished |

### Minimum specs for parking-empty-alert

| Setup | RAM | CPU | Disk |
|---|---|---|---|
| 1 camera, no LPR | 1 GB free | Dual-core 1.5 GHz | 30 GB |
| 1 camera + LPR | 2 GB free | Quad-core or GPU | 50 GB |
| 3 cameras | 3 GB free | Quad-core | 100 GB |
| 5+ cameras + LPR | 4 GB free | Quad-core + Coral USB | 200 GB |

### Compatible NAS models (tested)

| Model | CPU | RAM | Verdict |
|---|---|---|---|
| **Synology DS220+** | Intel Celeron J4025 | 2GB (upgradable to 6GB) | ✅ Works for 1-2 cameras |
| **Synology DS920+** | Intel Celeron J4125 | 4GB (upgradable to 8GB) | ✅ Recommended, handles 3-4 cameras |
| **Synology DS923+** | AMD Ryzen R1600 | 4GB ECC (upgradable) | ✅ Excellent, supports 5+ cameras |
| **Synology DS1522+** | AMD Ryzen R1600 | 8GB ECC (upgradable to 32GB) | ✅ Best Synology for this project |
| **QNAP TS-453D** | Intel Celeron J4125 | 4GB (upgradable) | ✅ Good, 3-4 cameras |
| **QNAP TS-464** | Intel N5095 | 4GB | ✅ Good performance |
| **UnRAID — any x86 build** | Anything Quad-core+ | 8GB+ | ✅ Most flexible |
| **TrueNAS SCALE** | Anything Quad-core+ | 16GB+ | ⚠️ Works but K3s/Helm complexity |

### Not recommended

| Model | Why |
|---|---|
| Synology DS218 (non-+) | ARM CPU — Frigate has limited ARM support, no hardware accel |
| Synology J-series (DS220j, DS118) | Too slow CPU + low RAM ceiling |
| QNAP TS-251D (single Bay) | RAM limit too low for AI workloads |
| Any USB-attached cloud drive | Not real NAS, unstable for 24/7 |

## Common considerations across all NAS

### Network mode

The main `docker-compose.yml` uses `network_mode: host` for Home Assistant. On NAS UIs, this is often not exposed in the GUI — you'll need either:

1. **CLI deployment** (recommended) — use SSH + docker compose, full feature parity
2. **GUI deployment with bridge mode** — Use `docker-compose.macwin.yml` override, manually configure ports

Most NAS users prefer CLI. Each guide covers both.

### Storage paths

Don't deploy to USB drives or external volumes that may unmount. Use the NAS's main pool.

Recommended paths:

| NAS | Stack location | Recordings location |
|---|---|---|
| **Synology** | `/volume1/docker/parking-empty-alert/` | `/volume1/docker/parking-empty-alert/frigate-storage/` |
| **UnRAID** | `/mnt/user/appdata/parking-empty-alert/` | `/mnt/user/appdata/parking-empty-alert/frigate-storage/` |
| **QNAP** | `/share/Container/parking-empty-alert/` | `/share/Container/parking-empty-alert/frigate-storage/` |

### Performance: NAS-specific concerns

**SMR vs CMR disks:** Frigate writes continuously (motion recordings). SMR (Shingled Magnetic Recording) drives slow down dramatically under sustained writes. Check your drives:
- **CMR drives (recommended):** WD Red Plus, Seagate IronWolf, HGST/WD Ultrastar
- **SMR drives (avoid for Frigate):** WD Red (without "Plus"), Seagate Barracuda 2.5"

**Cache:** Most NAS have SSD cache. Configure it as **read-write** cache for Frigate's recording volume. Reduces write amplification on HDDs.

**RAID level:** Frigate is tolerant of single-disk failure. RAID 5/6 or SHR is fine. Don't use RAID 0.

### Power management

Configure NAS to **never** sleep disk drives:
- Frigate's continuous writes prevent spin-down anyway
- Sleeping disks waste minutes spinning back up if Frigate hiccups

In NAS UI:
- **Synology:** Control Panel → Hardware → HDD Hibernation → Disable
- **UnRAID:** Settings → Disk Settings → Default Spin Down Delay → Never
- **QNAP:** Control Panel → Hardware → HDD → Disable Disk Standby

### Backup strategy

| Backup target | What |
|---|---|
| **NAS snapshot** (Btrfs, ZFS) | Frequent (hourly), of `config/` directory |
| **Off-site sync** (cloud, 2nd NAS) | Daily, of `config/` + `.env` |
| **External USB** | Weekly cold backup |

**Don't back up Frigate recordings** — they're huge and replaceable. Just back up configs.

### Updates

NAS users often delay updates ("if it ain't broke..."). For this project:
- **Stack updates** (parking-empty-alert): `docker pull ghcr.io/marczyn/parking-empty-alert:latest && docker restart parking`
- **NAS firmware updates** (DSM, UnRAID OS, QTS): Apply when convenient — usually safe; back up first

## Next steps

Pick your NAS guide:

- 🟦 [**Synology DSM**](synology.md)
- 🟧 [**UnRAID**](unraid.md)
- 🟩 [**QNAP QTS**](qnap.md)

Or, if you don't have a NAS and want recommendations, see the [hardware recommendations table in the main README](../../README.md#hardware-recommendations).
