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

# Check secrets.yaml — must contain placeholder values
if git diff --cached --name-only | grep -q 'config/homeassistant/secrets.yaml$'; then
  if ! grep -qE '(change_this|zmien_to|1234567|placeholder|TEMPLATE)' config/homeassistant/secrets.yaml; then
    echo "❌ secrets.yaml looks like real values, not template!"
    echo "   Verify it has placeholder strings before committing."
    echo "   Real values for that file go into .env (which is gitignored)."
    ERRORS=$((ERRORS+1))
  fi
fi

# Block CallMeBot APIKEY look-alikes (6-9 digit numbers near 'apikey' string).
# CallMeBot APIKEY range is 6-9 digits depending on registration era.
LEAKS=$(git diff --cached -U0 | grep -E '^\+.*apikey.*[0-9]{6,9}' | grep -vE '1234567|123456789' || true)
if [ -n "$LEAKS" ]; then
  echo "❌ Possible CallMeBot APIKEY leak in staged changes:"
  echo "$LEAKS"
  ERRORS=$((ERRORS+1))
fi

# Block phone number look-alikes
LEAKS=$(git diff --cached -U0 | grep -E '^\+.*whatsapp_phone:.*"[1-9][0-9]{10,14}"' | grep -vE '48501234567' || true)
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
