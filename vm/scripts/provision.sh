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

# Remove cloud-init seed data so it doesn't run again
sudo cloud-init clean --logs

sudo mkdir -p /var/lib/parking

echo "==> Provisioning complete."
