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

# Extract backup. A backup may have been copied from another host (backup.sh documents
# scp / the 3-2-1 rule), so treat the archive as semi-trusted: reject absolute paths and
# '..' traversal members BEFORE extracting, and confine extraction to the project dir.
# (No `2>/dev/null` — tar's own warnings must stay visible.)
echo "Extracting $BACKUP_FILE..."
if tar tzf "$BACKUP_FILE" | grep -qE '(^/|(^|/)\.\.(/|$))'; then
  echo "❌ Refusing to restore: archive contains absolute or '..' paths (possible path traversal)."
  exit 1
fi
# Name-only checks are blind to symlink/hardlink TARGETS: a member symlinking `config`->/etc
# then a regular `config/passwd` would write through the link, escaping -C. Reject any link
# member (the long-listing type char is 'l'/'h'); backup.sh never creates links.
if tar tvzf "$BACKUP_FILE" | grep -qE '^[lh]'; then
  echo "❌ Refusing to restore: archive contains symlink/hardlink members (possible traversal)."
  exit 1
fi
tar xzf "$BACKUP_FILE" -C "$PWD"

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
