#!/bin/bash
###############################################################################
# Parking Empty Alert — Backup Script
#
# Creates a compressed archive of:
#   - .env (secrets)
#   - config/ (all configurations)
#   - docker-compose.yml + overrides
#
# Excludes: frigate-storage (recordings — too large to back up daily)
#
# Run:  bash scripts/backup.sh [/optional/output/path]
###############################################################################
set -euo pipefail

cd "$(dirname "$0")/.."
PROJ=$(pwd)

OUTPUT_DIR="${1:-.}"
# PID suffix prevents same-second collisions if backup.sh runs in parallel
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="parking-empty-alert-backup-${TIMESTAMP}-$$.tar.gz"
BACKUP_PATH="${OUTPUT_DIR}/${BACKUP_NAME}"

# Sanity checks
if [ ! -f docker-compose.yml ]; then
  echo "❌ Must run from the parking-empty-alert directory (or its parent)"
  exit 1
fi

if [ ! -f .env ]; then
  echo "⚠ Warning: .env not found. Backup will not include secrets."
fi

# Resolve final output path
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
BACKUP_PATH="${OUTPUT_DIR}/${BACKUP_NAME}"

echo "Creating backup: $BACKUP_PATH"
echo

# Build file list — include configs, exclude recordings
INCLUDES=(
  docker-compose.yml
  docker-compose.macwin.yml
  config/
)

# Include .env only if it exists
[ -f .env ] && INCLUDES+=(.env)

# Include LPR overrides if present
[ -f examples/lpr/docker-compose.lpr.yml ] && INCLUDES+=(examples/lpr/docker-compose.lpr.yml)

# Verify each path exists before tarring
EXISTING=()
for p in "${INCLUDES[@]}"; do
  [ -e "$p" ] && EXISTING+=("$p")
done

# Create archive
tar czf "$BACKUP_PATH" \
  --exclude='./.git' \
  --exclude='./node_modules' \
  --exclude='./.venv' \
  --exclude='__pycache__' \
  --exclude='config/homeassistant/.storage' \
  --exclude='config/homeassistant/.cloud' \
  --exclude='config/homeassistant/home-assistant.log*' \
  --exclude='config/homeassistant/home-assistant_v2.db*' \
  --exclude='config/homeassistant/deps' \
  --exclude='config/homeassistant/tts' \
  --exclude='config/homeassistant/www' \
  --exclude='config/homeassistant/custom_components' \
  --exclude='*.pyc' \
  --exclude='*.swp' \
  --exclude='.DS_Store' \
  "${EXISTING[@]}"

# Set permissions
chmod 600 "$BACKUP_PATH"

# Verify
SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
COUNT=$(tar tzf "$BACKUP_PATH" | wc -l)

echo "✅ Backup created: $BACKUP_PATH"
echo "   Size:  $SIZE"
echo "   Files: $COUNT"
echo
echo "⚠️ SECURITY: This archive contains .env with RTSP credentials,"
echo "   MQTT password, WhatsApp APIKEY, and phone number. Do NOT share."
echo "   For sharing-safe backup, remove .env before tar (config only)."
echo
echo "💡 To restore:"
echo "   cd /path/to/restore/location"
echo "   tar xzf '$BACKUP_PATH'"
echo "   docker compose up -d"
echo
echo "💡 To copy to remote (example):"
echo "   scp '$BACKUP_PATH' user@remote-host:/backups/"
echo "   rsync -av '$BACKUP_PATH' user@remote-host:/backups/"
echo
echo "📋 Keep backups in 3-2-1 rule: 3 copies, 2 media types, 1 off-site."
