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

# ── 5. Network portability: remove the build-time NIC pin ──────────────────────
# Build-time cloud-init wrote a network profile MATCHED TO THIS BUILD VM's NIC (its
# kernel name / MAC). On a different hypervisor (Synology VMM / ESXi) the NIC has a
# different name+MAC → that pinned profile never matches → no DHCP → no IP → the whole
# appliance is dead (no image pull, no services, no SSH). Make the shipped image fully
# portable: (1) force a STABLE interface name (eth0) on every hypervisor by disabling
# predictable naming, (2) ship a plain "eth0 DHCP" profile that always matches, (3) stop
# cloud-init from re-pinning the network. ifupdown + isc-dhcp-client (DHCP also writes
# resolv.conf, so DNS works) are the deterministic single network manager.
# NB: nothing here restarts networking — changes take effect on the shipped image's
# first boot only, so the live Packer SSH session survives.
echo "==> Hardening network for cross-hypervisor portability..."
# ifupdown + isc-dhcp-client ship on the Debian cloud image already; only fetch lists
# (removed by the cleanup section above) + install if something is actually missing.
if ! dpkg -s ifupdown isc-dhcp-client >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends ifupdown isc-dhcp-client
fi
sudo sed -i 's/\(GRUB_CMDLINE_LINUX="[^"]*\)"/\1 net.ifnames=0 biosdevname=0"/' /etc/default/grub
sudo update-grub
sudo rm -f /etc/netplan/50-cloud-init.yaml /etc/network/interfaces.d/50-cloud-init
sudo tee /etc/network/interfaces.d/60-parking >/dev/null <<'EOF'
auto eth0
iface eth0 inet dhcp
EOF
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network.cfg >/dev/null
sudo systemctl enable networking 2>/dev/null || true
sudo systemctl disable systemd-networkd.service systemd-networkd.socket 2>/dev/null || true

# Remove cloud-init seed data so it doesn't run again
sudo cloud-init clean --logs

sudo mkdir -p /var/lib/parking

echo "==> Provisioning complete."
