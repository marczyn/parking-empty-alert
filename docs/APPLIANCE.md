# 💿 Virtual appliance (OVA / qcow2)

A pre-baked virtual machine: import it, power on, answer the first-boot wizard — no
Docker knowledge required. The application image is **baked into the image**, so the
first boot works **fully offline** (no internet/DNS needed).

Two variants:
- **full** — Frigate + Home Assistant + Mosquitto, all in one VM.
- **lite** — Frigate + Mosquitto only, for connecting to your **existing** Home Assistant.

## Get the image

The OVA/qcow2 files are **not attached to GitHub releases** — with the app image baked
in, each file is 4.6–11 GB, over GitHub's 2 GiB release-asset limit. Build them yourself
(both variants are E2E-validated):

- **Via CI** (recommended): `gh workflow run build-vm.yml -f version=1.2.0`, then download
  the `ova-full` / `ova-lite` / `qcow2-full` / `qcow2-lite` run artifacts (7-day retention).
- **Locally** (needs [Packer](https://www.packer.io/) + QEMU):
  ```bash
  packer init vm/parking.pkr.hcl
  packer build -var variant=lite -var version=1.2.0 vm/parking.pkr.hcl   # or variant=full
  # → output/ova/parking-empty-alert-lite-1.2.0.ova
  # → output/lite/parking-empty-alert-lite-1.2.0.qcow2
  ```

Use the **`.ova`** for VMware / VirtualBox / Synology VMM, or the **`.qcow2`** for
QEMU / KVM / Proxmox / libvirt (which don't import OVA natively).

## Requirements

| Resource | Default | Notes |
|---|---|---|
| vCPU | 2 | bump for more cameras |
| RAM | 2 GB | bump for the full variant / more cameras |
| Disk | 12 GB | thin/sparse; grows with recordings |

The image ships a **generic kernel with all storage/NIC drivers**, so it boots unmodified
on any common controller (VMware LSI Logic / PVSCSI / SATA, VirtualBox, Hyper-V, KVM/virtio,
Synology VMM) — no manual driver or hardware tweaks needed.

## Import

### VMware ESXi / vCenter / Workstation / Fusion
**Deploy OVF Template** → select the `.ova` → accept defaults → finish. It boots on the
default LSI Logic controller.

### Synology Virtual Machine Manager (VMM)
**Image → Import → Import .ova file**, then **Virtual Machine → Create** from that image.

### VirtualBox
**File → Import Appliance** → select the `.ova` → **Import**.

### Proxmox VE / QEMU-KVM / libvirt
Use the **`.qcow2`**. On Proxmox:
```bash
# create a VM (any id, no disk), then:
qm importdisk <vmid> parking-empty-alert-lite-1.2.0.qcow2 <storage>
qm set <vmid> --scsihw virtio-scsi-single --scsi0 <storage>:vm-<vmid>-disk-0
qm set <vmid> --boot order=scsi0
```

### Microsoft Hyper-V
Hyper-V can't import OVA directly — convert the qcow2 to VHDX first:
```bash
qemu-img convert -O vhdx parking-empty-alert-lite-1.2.0.qcow2 parking.vhdx
```
then create a **Generation 1** VM using `parking.vhdx` as its disk.

## First boot

1. **Power on.** The appliance picks up an IP automatically via **DHCP**.
2. On the **VM console**, the **first-boot wizard** runs and asks for:
   - Network — DHCP (default) or a static IP / CIDR / gateway / DNS
   - Camera IP + RTSP username/password + camera brand (Reolink / Hikvision / Dahua / Tapo / custom)
   - **lite:** MQTT username/password (the credentials your external HA will use)
   - **full:** WhatsApp number + [CallMeBot](https://www.callmebot.com/) API key
3. It starts the container and prints the access URLs.

## After setup

- **Frigate UI:** `http://<appliance-ip>:8090`
- **full** — **Home Assistant:** `http://<appliance-ip>:8123`
- **lite** — in your existing Home Assistant, add the **MQTT** integration → broker
  `<appliance-ip>`, port **1883**, with the username/password you set; and the **Frigate**
  integration → `http://<appliance-ip>:8090`
- Draw your parking zone: **Frigate UI → camera → Settings → Edit Zones**.

To re-run the wizard, delete the sentinel and reboot:
```bash
sudo rm /var/lib/parking/.configured && sudo reboot
```
