#!/bin/bash
###############################################################################
# Parking Empty Alert — Restore Script
#
# Restores a backup archive created by scripts/backup.sh.
# Run: bash scripts/restore.sh /path/to/parking-empty-alert-backup-YYYYMMDD-HHMMSS.tar.gz
###############################################################################
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: bash scripts/restore.sh <backup-file.tar.gz>"
  echo
  echo "Example:"
  echo "  bash scripts/restore.sh ~/parking-empty-alert-backup-20260607-090000.tar.gz"
  exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "❌ Backup file not found: $BACKUP_FILE"
  exit 1
fi

cd "$(dirname "$0")/.."

# Confirm overwrite
if [ -f .env ] || [ -d config ]; then
  echo "⚠ Restore will OVERWRITE existing files:"
  [ -f .env ] && echo "  - .env"
  [ -d config ] && echo "  - config/"
  echo
  read -r -p "Continue? [y/N]: " CONFIRM
  CONFIRM_LC=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
  if [ "$CONFIRM_LC" != "y" ]; then
    echo "Aborted."
    exit 0
  fi
fi

# Stop stack before restoring (avoid file lock issues)
echo "Stopping containers..."
docker compose down 2>/dev/null || true

# Extract backup
echo "Extracting $BACKUP_FILE..."
tar xzf "$BACKUP_FILE"

# Restore safe permissions on secret files
[ -f .env ] && chmod 600 .env
[ -f config/passwd ] && chmod 600 config/passwd
[ -f config/homeassistant/secrets.yaml ] && chmod 600 config/homeassistant/secrets.yaml

echo "✅ Restore complete (secrets chmod 600)."
echo
echo "Verify config:"
echo "  cat .env"
echo "  ls config/"
echo
echo "Start the stack:"
echo "  docker compose up -d"
echo
echo "Watch logs to ensure healthy start:"
echo "  docker compose logs -f --tail=50"
