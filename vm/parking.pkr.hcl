packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

# ── Variables ──────────────────────────────────────────────────────────────────

variable "variant" {
  type        = string
  default     = "full"
  description = "full or lite"
  validation {
    condition     = contains(["full", "lite"], var.variant)
    error_message = "Variant must be 'full' or 'lite'."
  }
}

variable "version" {
  type    = string
  default = "1.0.2"
}

variable "disk_size" {
  type    = string
  default = "12288"  # 12 GB — Docker images + recordings headroom
}

variable "memory" {
  type    = string
  default = "2048"
}

variable "cpus" {
  type    = string
  default = "2"
}

# Debian 12 (bookworm) generic cloud image — updated periodically upstream
variable "debian_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
}

variable "debian_checksum" {
  type    = string
  default = "file:https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS"
}

# ── Locals ─────────────────────────────────────────────────────────────────────

locals {
  vm_name    = "parking-empty-alert-${var.variant}-${var.version}"
  image_name = var.variant == "full" ? "ghcr.io/marczyn/parking-empty-alert:latest" : "ghcr.io/marczyn/parking-empty-alert-lite:latest"
}

# ── Source ─────────────────────────────────────────────────────────────────────

source "qemu" "parking" {
  iso_url          = var.debian_url
  iso_checksum     = var.debian_checksum
  disk_image       = true

  output_directory = "output/${var.variant}"
  vm_name          = "${local.vm_name}.qcow2"

  cpus             = var.cpus
  memory           = var.memory
  disk_size        = var.disk_size
  format           = "qcow2"

  # Use KVM if available; fall back to TCG (slower but works without /dev/kvm)
  accelerator      = "kvm"

  boot_wait        = "12s"

  # Packer SSHes in using the temporary password set by build-time cloud-init
  ssh_username     = "debian"
  ssh_password     = "packer-build"
  ssh_timeout      = "8m"

  shutdown_command = "echo 'packer-build' | sudo -S shutdown -P now"

  # Seed ISO: provides cloud-init user-data + meta-data for the build session
  cd_files         = ["vm/cloud-init/"]
  cd_label         = "cidata"

  qemuargs = [
    ["-machine", "accel=kvm:tcg"],
    ["-cpu",     "host"],
    ["-smp",     "${var.cpus}"],
  ]
}

# ── Build ──────────────────────────────────────────────────────────────────────

build {
  name    = "parking-${var.variant}"
  sources = ["source.qemu.parking"]

  # Wait for cloud-init to finish its own configuration pass
  provisioner "shell" {
    inline = [
      "sudo cloud-init status --wait --long || true",
      "echo 'cloud-init done'",
    ]
  }

  # Upload all runtime files to /tmp
  provisioner "file" {
    sources = [
      "vm/files/parking-wizard.sh",
      "vm/files/parking-wizard.service",
      "vm/files/parking.service",
    ]
    destination = "/tmp/"
  }

  # Main provisioning: Docker, systemd units, wizard
  provisioner "shell" {
    environment_vars = [
      "VARIANT=${var.variant}",
      "IMAGE_NAME=${local.image_name}",
    ]
    script = "vm/scripts/provision.sh"
  }

  # Convert qcow2 → VMDK → OVA
  post-processor "shell-local" {
    environment_vars = [
      "VARIANT=${var.variant}",
      "VERSION=${var.version}",
      "VM_NAME=${local.vm_name}",
    ]
    script = "vm/scripts/make-ova.sh"
  }
}
