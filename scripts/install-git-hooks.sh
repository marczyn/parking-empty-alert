#!/bin/bash
###############################################################################
# Install git pre-commit hook that blocks accidental secret leaks.
#
# Run once:  bash scripts/install-git-hooks.sh
###############################################################################
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d .git ]; then
  echo "❌ Not a git repository. Run this from a cloned parking-empty-alert."
  exit 1
fi

cat > .git/hooks/pre-commit <<'HOOK'
#!/bin/bash
# Pre-commit hook: refuse to commit secrets
set -euo pipefail

ERRORS=0

# Block .env from being committed (gitignored, but if user used git add -f)
if git diff --cached --name-only | grep -qE '(^|/)\.env$'; then
  echo "❌ Refusing to commit .env — contains real secrets."
  echo "   Did you mean to commit .env.example?"
  ERRORS=$((ERRORS+1))
fi

# Block config/passwd
if git diff --cached --name-only | grep -qE 'config/passwd$|config/.*/passwd$'; then
  echo "❌ Refusing to commit Mosquitto password file."
  ERRORS=$((ERRORS+1))
fi

# Check secrets.yaml — scan the STAGED BLOB (not the working tree) and require EVERY
# secret field to still equal its template value. A positive per-field assertion (vs the
# old "any one placeholder substring exists" check) blocks a file that mixes a real
# mqtt_password with an unedited example apikey line.
if git diff --cached --name-only | grep -q 'config/homeassistant/secrets.yaml$'; then
  SECRETS_BLOB=$(git show ":config/homeassistant/secrets.yaml" 2>/dev/null || true)
  SECRETS_BAD=0
  printf '%s\n' "$SECRETS_BLOB" | grep -qE '^[[:space:]]*mqtt_password:[[:space:]]*change_this_password_too[[:space:]]*$'    || SECRETS_BAD=1
  printf '%s\n' "$SECRETS_BLOB" | grep -qE '^[[:space:]]*whatsapp_phone:[[:space:]]*"?48501234567"?[[:space:]]*$'           || SECRETS_BAD=1
  printf '%s\n' "$SECRETS_BLOB" | grep -qE '^[[:space:]]*whatsapp_apikey:[[:space:]]*"?1234567"?[[:space:]]*$'              || SECRETS_BAD=1
  if [ "$SECRETS_BAD" -ne 0 ]; then
    echo "❌ secrets.yaml has non-placeholder (real?) values — every secret field must still"
    echo "   equal its template (mqtt_password / whatsapp_phone / whatsapp_apikey)."
    echo "   Real values for that file go into .env (which is gitignored)."
    ERRORS=$((ERRORS+1))
  fi
fi

# Block CallMeBot APIKEY look-alikes (6-9 digit numbers near 'apikey' string).
# CallMeBot APIKEY range is 6-9 digits depending on registration era.
# Exclusion is ANCHORED to the exact placeholder value (with optional quotes and a
# non-digit/end boundary) so a real key that merely CONTAINS 1234567 (e.g. 91234567,
# 12345670) is still flagged, not dropped as a substring match.
LEAKS=$(git diff --cached -U0 | grep -E '^\+.*apikey.*[0-9]{6,9}' | grep -vE 'apikey[^0-9]*"?(1234567|123456789)"?([^0-9]|$)' || true)
if [ -n "$LEAKS" ]; then
  echo "❌ Possible CallMeBot APIKEY leak in staged changes:"
  echo "$LEAKS"
  ERRORS=$((ERRORS+1))
fi

# Block phone number look-alikes
LEAKS=$(git diff --cached -U0 | grep -E '^\+.*whatsapp_phone:.*"[1-9][0-9]{10,14}"' | grep -vE 'whatsapp_phone:[^0-9]*"?48501234567"?([^0-9]|$)' || true)
if [ -n "$LEAKS" ]; then
  echo "❌ Possible WhatsApp phone leak in staged changes:"
  echo "$LEAKS"
  ERRORS=$((ERRORS+1))
fi

if [ $ERRORS -gt 0 ]; then
  echo
  echo "Commit blocked: $ERRORS issue(s). Fix above, then retry."
  echo "(To bypass for emergency: git commit --no-verify — but verify manually first!)"
  exit 1
fi

exit 0
HOOK

chmod +x .git/hooks/pre-commit

echo "✓ Git pre-commit hook installed."
echo
echo "From now on, 'git commit' will refuse to:"
echo "  • Commit .env (contains real secrets)"
echo "  • Commit Mosquitto passwd file"
echo "  • Commit secrets.yaml with non-placeholder values"
echo "  • Commit anything that looks like a CallMeBot APIKEY or phone number"
