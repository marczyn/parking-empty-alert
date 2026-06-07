# 🌐 Multi-VLAN Setup

When cameras are isolated in one VLAN (typical IoT segregation) and Frigate +
Home Assistant run in another VLAN (main LAN or trusted segment).

## The problem

Common security setup:
- **VLAN 30 (IoT):** cameras, smart bulbs, thermostats — no internet, no LAN access
- **VLAN 10 (Trusted):** PCs, NAS, Docker host running Frigate + HA

Frigate (in VLAN 10) needs RTSP from cameras (in VLAN 30) — but VLANs are isolated
by default.

## 4 solutions (pick what fits your network)

| Solution | Setup complexity | When to use |
|---|---|---|
| **[A) Firewall allow rule](#a-firewall-allow-rule-recommended)** | Easy | You control your router/L3 switch — best for most users |
| **[B) Multi-homed Docker host](#b-multi-homed-docker-host)** | Medium | Docker host can have 2 NICs (one per VLAN) |
| **[C) RTSP restream proxy](#c-rtsp-restream-proxy)** | Medium | You want zero cross-VLAN traffic except RTSP |
| **[D) Synology as bridge](#d-synology-as-bridge)** | Easy if you have Synology | Synology already runs in IoT VLAN with cameras |

---

## A) Firewall allow rule (recommended)

Add a **one-way** firewall rule allowing Frigate to reach the cameras.

### Example — pfSense / OPNsense

```
Firewall → Rules → VLAN 10 (Trusted) → Add:
  Action:        Pass
  Interface:     VLAN10
  Source:        single host → <Frigate Docker host IP>
  Destination:   network → <VLAN 30 subnet, e.g., 192.168.30.0/24>
  Port:          554 (RTSP), and optionally 80, 8000, 8554 (camera UIs/ONVIF)
  Description:   Allow Frigate to reach cameras
```

Then VLAN 30 firewall doesn't need a return rule — pfSense allows return traffic
automatically (stateful).

### Example — UniFi Network (UCG/UDM)

```
Settings → Security → Firewall → Internet & Network → LAN In:
  Add rule:
    Name:         Frigate → Cameras
    Action:       Accept
    Source:       <Frigate Docker host IP>/32
    Destination:  <VLAN 30 IoT> network
    Port:         554
```

### Example — MikroTik (RouterOS)

```bash
/ip firewall filter
add chain=forward action=accept \
    src-address=192.168.10.50 \
    dst-address=192.168.30.0/24 \
    dst-port=554 protocol=tcp \
    comment="Frigate to cameras"
```

### Verify

From Docker host (in VLAN 10):
```bash
nc -zv 192.168.30.100 554       # Camera IP + RTSP port
# Expected: Connection to 192.168.30.100 554 port [tcp/rtsp] succeeded!
```

### Pros & cons

✅ **Pros:**
- Standard, well-understood approach
- Zero changes to Frigate / HA / cameras
- One-way rule — cameras still can't initiate connections to LAN
- Easy to audit + rollback

⚠️ **Cons:**
- Frigate host IP must be static
- If host changes IP, rule breaks

### After firewall rule, configure normally

In `config/frigate.yml`, just use camera's VLAN 30 IP:

```yaml
inputs:
  - path: rtsp://USER:PASS@192.168.30.100:554/h264Preview_01_sub
    roles: [detect]
```

No other changes needed — Frigate doesn't care about VLANs, only that the
TCP connection succeeds.

---

## B) Multi-homed Docker host

Docker host has **two NICs** — one in each VLAN. Frigate sees cameras directly
without firewall rules.

### Architecture

```
┌──────────────────────────┐
│      Docker host          │
│                           │
│  eth0 ─→ VLAN 10 (Trusted)  ←── HA web access from LAN
│  eth1 ─→ VLAN 30 (IoT)       ←── Frigate RTSP to cameras
│                           │
│  Frigate container         │
│  HA container               │
└──────────────────────────┘
```

### Setup (Linux Docker host)

If your host already has 2 physical NICs:
1. Configure `eth1` with IP in VLAN 30 subnet (e.g., `192.168.30.50`)
2. No firewall rules needed
3. Frigate (in network_mode: host) sees cameras via eth1

If you have VLAN-tagging switch:
```bash
# Add VLAN 30 sub-interface to eth0 (tagged VLAN)
sudo ip link add link eth0 name eth0.30 type vlan id 30
sudo ip addr add 192.168.30.50/24 dev eth0.30
sudo ip link set eth0.30 up
```

Make persistent in `/etc/netplan/01-vlans.yaml` or `/etc/network/interfaces`
(depending on your distro).

### Pros & cons

✅ **Pros:**
- Zero firewall changes
- No additional routing decisions
- Frigate sees cameras as "local"

⚠️ **Cons:**
- Requires Docker host with 2 NICs OR VLAN-tagging switch
- More complex network setup on host
- Docker host now "touches" both VLANs (security implication)

---

## C) RTSP restream proxy

Put a small proxy container **inside VLAN 30** (camera VLAN) that restreams
RTSP from cameras to Frigate over the trusted VLAN's network.

### Architecture

```
VLAN 30 (cameras):                VLAN 10 (Frigate):
┌─────────────┐                   ┌────────────────┐
│   Camera     │ ─RTSP─→  ┌──────┐ │                │
│              │          │ go2rtc │ ──RTSP─→  Frigate
│              │ ─RTSP─→  │ proxy  │              HA
└─────────────┘          └──────┘ │                │
                          (VLAN 30) │                │
                                    └────────────────┘
            ↑ ONE firewall rule:           
            Frigate → proxy:8554 (RTSP)
```

### Setup

#### 1. Run go2rtc in VLAN 30 (e.g., on Synology in IoT VLAN, or a small RPi)

`go2rtc.yaml`:
```yaml
streams:
  camera1: rtsp://USER:PASS@192.168.30.100:554/h264Preview_01_sub
  camera1_main: rtsp://USER:PASS@192.168.30.100:554/h264Preview_01_main

webrtc:
  listen: :8555

api:
  listen: :1984
```

`docker run`:
```bash
docker run -d --restart=always \
  --network=host \
  -v $(pwd)/go2rtc.yaml:/config/go2rtc.yaml \
  alexxit/go2rtc
```

#### 2. Add firewall rule (one port, one direction)

```
Allow: Frigate host → proxy host, port 8554 (RTSP)
```

#### 3. Configure Frigate to use the proxy

`config/frigate.yml`:
```yaml
inputs:
  - path: rtsp://192.168.30.50:8554/camera1
    roles: [detect]
  - path: rtsp://192.168.30.50:8554/camera1_main
    roles: [record]
```

(Where `192.168.30.50` is the go2rtc proxy host's IP.)

### Pros & cons

✅ **Pros:**
- Minimal firewall surface (1 port, 1 host pair)
- Cameras only talk to local proxy (faster, fewer issues)
- Proxy can multiplex one camera connection to multiple consumers
- Works for cameras that don't support multiple RTSP clients

⚠️ **Cons:**
- Requires additional host running go2rtc in IoT VLAN
- Extra hop adds ~100ms latency
- One more thing to maintain + monitor

---

## D) Synology as bridge

If you already have **Synology Surveillance Station running in your IoT VLAN**
with cameras attached, use it as the RTSP restream.

See [Synology Surveillance Station coexistence guide](synology-surveillance-station.md)
**Option B (RTSP restream)** — it covers this exact scenario.

```
VLAN 30:                          VLAN 10:
Cameras → Synology (SS RTSP restream) → Firewall rule (1 port) → Frigate
```

### Setup summary
1. Enable RTSP server in Surveillance Station UI
2. Add firewall rule: Frigate → Synology, port 554
3. Configure Frigate URLs to point at Synology

Detailed steps in the linked Synology guide.

---

## Recommended decision tree

```
Can you add firewall rules to your router?
├── YES, easy → Option A (firewall rule)
│
└── NO / restricted firewall →
    │
    Do you have hardware in the IoT VLAN that can run Docker/proxy?
    ├── YES, Synology → Option D (Synology bridge)
    ├── YES, other →    Option C (go2rtc proxy)
    └── NO →
        │
        Does your Docker host have 2 NICs or VLAN-tagging switch?
        ├── YES → Option B (multi-homed host)
        └── NO  → ⚠ You need at least one of the above
```

---

## FAQ

### My cameras have no internet access — does this matter?

**No.** Frigate doesn't need internet for the cameras — it only needs LAN
RTSP access. The firewall rule (Option A) only allows Frigate IN to cameras,
not cameras OUT to anywhere.

### Will my IoT VLAN still be isolated from the internet?

**Yes** (with Option A, C, or D). The firewall rule is one-way: Frigate → cameras.
Cameras still can't initiate connections to anywhere.

### What about multicast / mDNS discovery?

Frigate doesn't use mDNS for cameras — it uses **explicit RTSP URLs** in
config. mDNS isolation between VLANs is irrelevant.

### Performance — does cross-VLAN add latency?

- **Option A (firewall):** ~1-5ms added (one routing hop in your router)
- **Option B (multi-homed):** 0ms (no routing)
- **Option C (proxy):** ~100ms (extra restream + decode)
- **Option D (Synology bridge):** ~100-200ms (Synology restream + cross-VLAN)

For parking detection (5fps, 2-min anti-blink filter), all options are
functionally equivalent.

### HA also needs MQTT — does that cross VLANs?

In all 4 options, **Mosquitto runs on the Frigate side** (VLAN 10).
Frigate connects to local Mosquitto, HA connects to local Mosquitto.
No cross-VLAN MQTT.

### Can cameras still be reached from my phone via Surveillance Station / Reolink app?

**Yes.** Those apps connect through your normal phone-LAN path (if both
phone and cameras are in VLAN 30, direct) or via cloud relay (Reolink app).
Adding Frigate as another consumer doesn't change anything.

---

## Related guides

- [Installation Guide](INSTALLATION.md) — main setup
- [Synology Surveillance Station coexistence](synology-surveillance-station.md) — if SS is already running
- [Non-Reolink camera templates](../examples/cameras/README.md) — RTSP URL formats per vendor
