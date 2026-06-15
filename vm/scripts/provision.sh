#!/bin/bash
# Packer provisioner: installs Docker, deploys wizard and systemd units.
# Runs as the 'debian' user with passwordless sudo.
set -euo pipefail

VARIANT="${VARIANT:-full}"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/marczyn/parking-empty-alert:latest}"

echo "==> Provisioning parking-empty-alert VM (variant: ${VARIANT})"

# ── 1. Install Docker ──────────────────────────────────────────────────────────
echo "==> Installing Docker..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    openssh-server

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -qq
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo systemctl enable docker
sudo usermod -aG docker debian

# ── 1b. Bake the application image INTO the appliance (offline first boot) ──────
# Pull the pinned app image at BUILD time so it ships INSIDE the OVA disk. The
# appliance then starts on first boot with NO internet/DNS. Previously the first-boot
# wizard pulled from ghcr.io, so a deployment without working network/DNS (exactly what
# happens behind many home/VMM setups) left the appliance permanently dead.
echo "==> Baking application image ${IMAGE_NAME} into the appliance..."
sudo systemctl start docker
timeout 600 bash -c 'until sudo docker info >/dev/null 2>&1; do sleep 2; done'
sudo docker pull "$IMAGE_NAME"

# ── 2. Write variant marker ────────────────────────────────────────────────────
echo "==> Writing variant config..."
sudo tee /etc/parking-variant <<EOF
VARIANT=${VARIANT}
IMAGE_NAME=${IMAGE_NAME}
EOF

# ── 3. Install wizard and systemd units ───────────────────────────────────────
echo "==> Installing wizard..."
sudo install -m 0755 /tmp/parking-wizard.sh /usr/local/bin/parking-wizard

echo "==> Installing systemd units..."
sudo install -m 0644 /tmp/parking-wizard.service /etc/systemd/system/parking-wizard.service
sudo install -m 0644 /tmp/parking.service        /etc/systemd/system/parking.service

# parking.service: substitute variant-specific image name
sudo sed -i "s|__IMAGE_NAME__|${IMAGE_NAME}|g" /etc/systemd/system/parking.service

# parking.service: publish the variant-specific port. 8090/8554/8555 (Frigate UI/RTSP/
# WebRTC) are common to both. The FULL image bundles Home Assistant, so it publishes 8123.
# The LITE image has NO bundled HA; it instead exposes its AUTHENTICATED MQTT broker on
# 1883 so your EXTERNAL Home Assistant can connect (the whole point of lite). Without this
# the lite broker runs but is unreachable from the LAN — the wizard tells the user to use
# <host>:1883 yet nothing is published there.
if [ "${VARIANT}" = "lite" ]; then
    VARIANT_PORTS="-p 1883:1883"
else
    VARIANT_PORTS="-p 8123:8123"
fi
sudo sed -i "s|__VARIANT_PORTS__|${VARIANT_PORTS}|g" /etc/systemd/system/parking.service

# parking-wizard runs on first boot; parking.service is enabled by the wizard
sudo systemctl daemon-reload
sudo systemctl enable parking-wizard.service

# ── 4. Harden & clean up ──────────────────────────────────────────────────────
echo "==> Cleaning up build artifacts..."
sudo apt-get autoremove -y
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

# Remove the packer build password, then FORCE the user to set one on first login
# (chage -d 0 expires it): otherwise the shipped image keeps a blank-password account
# that, combined with the cloud-init NOPASSWD:ALL sudo grant, is instant local root.
sudo passwd -d debian
sudo chage -d 0 debian

# Harden sshd for the SHIPPED image. The build-time cloud-init set
# `ssh_pwauth: true` (-> PasswordAuthentication yes in 50-cloud-init.conf) which is
# never otherwise reverted. Disable password auth entirely and never permit an empty
# password, so the blank build account can't be reached over SSH (key auth only).
sudo tee /etc/ssh/sshd_config.d/99-parking-hardening.conf >/dev/null <<'EOF'
PasswordAuthentication no
PermitEmptyPasswords no
EOF
sudo chmod 644 /etc/ssh/sshd_config.d/99-parking-hardening.conf

# Remove host SSH keys — regenerated on first boot
sudo rm -f /etc/ssh/ssh_host_*
sudo tee /etc/systemd/system/regenerate-ssh-host-keys.service <<'EOF'
[Unit]
Description=Regenerate SSH host keys on first boot
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_rsa_key

[Service]
Type=oneshot
ExecStart=/usr/sbin/dpkg-reconfigure openssh-server
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable regenerate-ssh-host-keys.service

# ── 5. Portability: stable NIC name, NetworkManager DHCP, VMware storage drivers ──
# Build-time cloud-init wrote a network profile MATCHED TO THIS BUILD VM's NIC (its
# kernel name / MAC). On a different hypervisor (Synology VMM / ESXi) the NIC has a
# different name+MAC → that pinned profile never matches → no DHCP → no IP → the whole
# appliance is dead. Make the shipped image fully portable:
# (1) force a STABLE interface name (eth0) on every hypervisor (disable predictable naming),
# (2) let the NetworkManager the cloud image ALREADY ships own eth0 via a persistent DHCP
#     keyfile — adding a second manager (ifupdown) only made NM mark eth0 "unmanaged" while
#     networking.service failed to raise the link, leaving the appliance with no DHCP,
# (3) stop cloud-init from re-pinning the network,
# (4) replace the Debian *cloud* kernel with the GENERIC kernel — the cloud kernel only
#     carries virtio + a couple of VMware paravirtual drivers (vmxnet3/vmw_pvscsi), so on
#     hypervisors that present other disk/NIC controllers (ESXi LSI Logic, VirtualBox/Hyper-V
#     SATA, e1000e, …) the root disk / NIC is invisible and the appliance drops to an
#     initramfs shell ("PARTUUID … does not exist") or comes up with no network.
# NB: nothing here restarts networking — changes take effect on the shipped image's first
# boot only, so the live Packer SSH session survives.
echo "==> Hardening for cross-hypervisor portability (eth0, NetworkManager, storage)..."

# NetworkManager ships on the Debian cloud image; install only if somehow absent.
if ! dpkg -s network-manager >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends network-manager
fi

sudo sed -i 's/\(GRUB_CMDLINE_LINUX="[^"]*\)"/\1 net.ifnames=0 biosdevname=0"/' /etc/default/grub
sudo update-grub

# Hand eth0 to NetworkManager: remove ifupdown/netplan profiles (their presence makes NM
# treat eth0 as unmanaged), then ship a persistent NM keyfile that DHCPs eth0 on every boot.
sudo rm -f /etc/netplan/50-cloud-init.yaml \
           /etc/network/interfaces.d/50-cloud-init \
           /etc/network/interfaces.d/60-parking
sudo install -d -m 0755 /etc/NetworkManager/system-connections
sudo tee /etc/NetworkManager/system-connections/eth0.nmconnection >/dev/null <<'EOF'
[connection]
id=eth0
type=ethernet
interface-name=eth0
autoconnect=true
autoconnect-priority=100

[ipv4]
method=auto

[ipv6]
method=auto
EOF
sudo chmod 600 /etc/NetworkManager/system-connections/eth0.nmconnection

echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network.cfg >/dev/null
sudo systemctl enable NetworkManager 2>/dev/null || true
sudo systemctl disable networking systemd-networkd.service systemd-networkd.socket 2>/dev/null || true

# (4) Universal kernel: install the GENERIC Debian kernel (full driver set) and force
# MODULES=most so the initramfs carries every storage/NIC driver, then drop the minimal
# cloud kernel so GRUB boots the generic one. The image then boots unmodified on any
# hypervisor (ESXi lsilogic/pvscsi/SATA, VirtualBox, Hyper-V, KVM/virtio, Synology VMM).
echo "==> Installing the generic kernel for universal hardware support..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends linux-image-amd64
echo 'MODULES=most' | sudo tee /etc/initramfs-tools/conf.d/00-most >/dev/null
sudo update-initramfs -u -k all

# Make GRUB boot the generic kernel instead of the cloud one. The cloud kernel is the
# *running* kernel during the Packer build, so `apt purge` of it hits an interactive
# "Abort kernel removal?" debconf prompt that DEFAULTS TO ABORT under a non-interactive
# frontend — leaving the cloud kernel installed and (being listed first) the GRUB default.
# Preseed that prompt to not-abort, purge, THEN unconditionally delete any leftover cloud
# kernel boot artifacts so update-grub physically cannot offer it. The build VM keeps
# running off the already-loaded kernel in RAM and never reboots before shutdown.
RUNNING_KERNEL="$(uname -r)"   # e.g. 6.1.0-49-cloud-amd64
echo "linux-image-${RUNNING_KERNEL} linux-image-${RUNNING_KERNEL}/prerm/removing-running-kernel-${RUNNING_KERNEL} boolean false" \
  | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y "linux-image-${RUNNING_KERNEL}" linux-image-cloud-amd64 2>/dev/null || true
sudo rm -f /boot/vmlinuz-*-cloud-amd64 /boot/initrd.img-*-cloud-amd64 \
           /boot/config-*-cloud-amd64 /boot/System.map-*-cloud-amd64
sudo update-grub
# Fail the build loudly if the generic kernel somehow isn't the only one GRUB will boot.
if grep -q 'cloud-amd64' /boot/grub/grub.cfg; then
    echo "ERROR: cloud kernel still referenced in grub.cfg" >&2; exit 1
fi
echo "==> GRUB now boots the generic kernel: $(ls /boot/vmlinuz-* | grep -v cloud)"

# Remove cloud-init seed data so it doesn't run again
sudo cloud-init clean --logs

sudo mkdir -p /var/lib/parking

echo "==> Provisioning complete."
