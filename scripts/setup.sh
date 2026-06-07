#!/bin/bash
###############################################################################
# Parking Empty Alert — Setup Script
# Run:  bash setup.sh
###############################################################################
set -euo pipefail

# Trap unexpected exits with a friendly message
trap 'EXIT_CODE=$?; if [ $EXIT_CODE -ne 0 ]; then
  echo
  echo "❌ setup.sh exited with code $EXIT_CODE at line $LINENO"
  echo "   If you pressed Ctrl+C or Ctrl+D, that is OK — re-run when ready."
  echo "   For real errors, see line above and check the README troubleshooting section."
fi' EXIT

cd "$(dirname "$0")/.."
PROJ=$(pwd)

# ─────────────────────────────────────────────────────────────
# 1. Check Docker
# ─────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "❌ Docker not installed. Install: https://docs.docker.com/get-docker/"
  exit 1
fi

# Bootstrap: ensure config/passwd exists so docker-compose mount works.
# Setup.sh below replaces it with hashes; this just prevents fresh-checkout fail.
[ -f config/passwd ] || cp config/passwd.example config/passwd 2>/dev/null || touch config/passwd

# Install git pre-commit hook (one-shot — idempotent)
if [ -d .git ] && [ ! -x .git/hooks/pre-commit ]; then
  bash scripts/install-git-hooks.sh 2>/dev/null || true
fi

# Validate hwaccel coupling — frigate.yml hwaccel_args without compose devices = fail
if grep -qE '^[[:space:]]*hwaccel_args:[[:space:]]*preset-vaapi' config/frigate.yml 2>/dev/null; then
  if ! grep -qE '^[[:space:]]*-[[:space:]]*/dev/dri:/dev/dri' docker-compose.yml; then
    echo "⚠ frigate.yml has 'hwaccel_args: preset-vaapi' but docker-compose.yml"
    echo "  doesn't expose /dev/dri. Frigate will fail to start."
    echo "  Uncomment the 'devices: [/dev/dri:/dev/dri]' block in docker-compose.yml"
    echo "  OR comment hwaccel_args in frigate.yml."
    echo
  fi
fi
if grep -qE '^[[:space:]]*hwaccel_args:[[:space:]]*preset-nvidia' config/frigate.yml 2>/dev/null; then
  if ! grep -qE 'driver:[[:space:]]*nvidia' docker-compose.yml; then
    echo "⚠ frigate.yml has 'hwaccel_args: preset-nvidia' but docker-compose.yml"
    echo "  doesn't reserve NVIDIA devices. Frigate will fail to start."
    echo
  fi
fi
# Coral USB TPU: edgetpu detector requires /dev/bus/usb passthrough
if grep -qE '^[[:space:]]*type:[[:space:]]*edgetpu' config/frigate.yml 2>/dev/null; then
  if ! grep -qE '^[[:space:]]*-[[:space:]]*/dev/bus/usb:/dev/bus/usb' docker-compose.yml; then
    echo "⚠ frigate.yml uses 'type: edgetpu' (Coral) but docker-compose.yml"
    echo "  doesn't expose /dev/bus/usb. Frigate will not find the Coral."
    echo
  fi
fi
# RPi / Rockchip hwaccel don't need extra device passthrough — driver in image

# Reject placeholder values from .env.example — they always indicate the user
# forgot to edit .env before running setup.sh.
# Check each suspicious key separately for robust pattern matching.
if [ -f .env ]; then
  PLACEHOLDER_FOUND=0
  while IFS='=' read -r KEY VAL; do
    case "$KEY" in
      RTSP_PASSWORD)
        case "$VAL" in
          change_this*|"") echo "❌ RTSP_PASSWORD is a placeholder: $VAL"; PLACEHOLDER_FOUND=1 ;;
        esac
        ;;
      WHATSAPP_PHONE)
        case "$VAL" in
          48501234567|1234567890*|"") echo "❌ WHATSAPP_PHONE is a placeholder: $VAL"; PLACEHOLDER_FOUND=1 ;;
        esac
        ;;
      WHATSAPP_APIKEY)
        case "$VAL" in
          1234567|"") echo "❌ WHATSAPP_APIKEY is a placeholder: $VAL"; PLACEHOLDER_FOUND=1 ;;
        esac
        ;;
      MQTT_PASSWORD)
        case "$VAL" in
          change_this*|"") echo "❌ MQTT_PASSWORD is a placeholder: $VAL"; PLACEHOLDER_FOUND=1 ;;
        esac
        ;;
    esac
  done < <(grep -E '^[A-Z_]+=' .env)

  if [ "$PLACEHOLDER_FOUND" -eq 1 ]; then
    echo
    echo "Please edit .env with your real values, OR delete .env to let"
    echo "setup.sh ask interactively."
    exit 1
  fi
fi
if ! docker compose version &>/dev/null && ! docker-compose version &>/dev/null; then
  echo "❌ Docker Compose not available. Update Docker."
  exit 1
fi
echo "✓ Docker OK"

# ─────────────────────────────────────────────────────────────
# 2. .env file
# ─────────────────────────────────────────────────────────────
if [ ! -f .env ]; then
  echo
  echo "════════════════════════════════════════════════════"
  echo "  STEP 1: Camera configuration"
  echo "════════════════════════════════════════════════════"
  read -r -p "Reolink camera IP (e.g., 192.168.1.100): " CAMERA_IP
  read -r -p "Reolink username (create a new 'frigate' user in Reolink UI with Viewer permission): " RTSP_USER

  # Password with confirmation — avoid silent typos
  while true; do
    read -r -s -p "Password for this account: " RTSP_PASSWORD; echo
    read -r -s -p "Confirm password: " RTSP_PASSWORD2; echo
    if [ "$RTSP_PASSWORD" = "$RTSP_PASSWORD2" ] && [ -n "$RTSP_PASSWORD" ]; then
      break
    fi
    echo "⚠ Passwords don't match or empty. Try again."
  done
  unset RTSP_PASSWORD2
  echo
  MQTT_PASSWORD=$(openssl rand -base64 24 2>/dev/null | tr -d '/+=' | head -c 20 || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 20)

  echo
  echo "════════════════════════════════════════════════════"
  echo "  STEP 1B: Timezone"
  echo "════════════════════════════════════════════════════"
  DEFAULT_TZ=$(cat /etc/timezone 2>/dev/null || readlink /etc/localtime 2>/dev/null | sed 's|.*zoneinfo/||' || echo "UTC")
  read -r -p "Timezone (IANA format, e.g. Europe/Warsaw, America/New_York) [$DEFAULT_TZ]: " TZ
  TZ=${TZ:-$DEFAULT_TZ}

  echo
  echo "════════════════════════════════════════════════════"
  echo "  STEP 1C: Docker host LAN IP (for HA iframe URLs)"
  echo "════════════════════════════════════════════════════"
  # Auto-detect primary LAN IP — pick the IP that reaches the default gateway,
  # which avoids docker0 / br- bridge networks (172.16.0.0/12 by default).
  DETECTED_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
  # Fallback: filter hostname -I for non-Docker ranges
  if [ -z "$DETECTED_IP" ]; then
    DETECTED_IP=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -vE '^(172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.|127\.)' | head -1)
  fi
  read -r -p "Docker host LAN IP (browser-accessible) [$DETECTED_IP]: " DOCKER_HOST_IP
  DOCKER_HOST_IP=${DOCKER_HOST_IP:-$DETECTED_IP}

  echo
  echo "════════════════════════════════════════════════════"
  echo "  STEP 2: WhatsApp (CallMeBot — free)"
  echo "════════════════════════════════════════════════════"
  echo "If you do NOT have a CallMeBot APIKEY yet:"
  echo "  1. Add +34 644 11 11 11 to phone contacts (as 'CallMeBot')"
  echo "  2. Open WhatsApp and send to this contact:"
  echo "     I allow callmebot to send me messages"
  echo "  3. Wait ~1 min for the reply — it will contain the APIKEY (7 digits)"
  echo
  read -r -p "Phone number (with country code, NO +; e.g., 48501234567): " WHATSAPP_PHONE
  read -r -p "CallMeBot APIKEY (7 digits): " WHATSAPP_APIKEY

  cat > .env <<EOF
CAMERA_IP=$CAMERA_IP
RTSP_USER=$RTSP_USER
RTSP_PASSWORD=$RTSP_PASSWORD
MQTT_USER=frigate
MQTT_PASSWORD=$MQTT_PASSWORD
WHATSAPP_PHONE=$WHATSAPP_PHONE
WHATSAPP_APIKEY=$WHATSAPP_APIKEY
TZ=$TZ
EOF
  chmod 600 .env
  echo "✓ .env created"

  # Update HA secrets.yaml
  cat > config/homeassistant/secrets.yaml <<EOF
# Auto-generated by setup.sh — edit only via setup.sh or manually
mqtt_user: frigate
mqtt_password: $MQTT_PASSWORD
whatsapp_phone: "$WHATSAPP_PHONE"
whatsapp_apikey: "$WHATSAPP_APIKEY"
EOF
  chmod 600 config/homeassistant/secrets.yaml

  # Substitute CAMERA_IP in frigate.yml
  sed -i.bak "s/CAMERA_IP_PLACEHOLDER/$CAMERA_IP/g" config/frigate.yml
  rm -f config/frigate.yml.bak

  # Make Frigate MQTT client_id unique to prevent collisions if user runs
  # multiple Frigate instances pointing at same broker. Substitute in base config
  # AND all example configs. Truncate to 23 chars for MQTT 3.1 compatibility.
  HN=$(hostname -s 2>/dev/null || echo "$RANDOM")
  CLIENT_ID=$(printf 'frigate-%s' "$HN" | cut -c1-23)
  for cfg in config/frigate.yml \
             examples/multi-camera/frigate.yml \
             examples/multi-spot-single-camera/frigate.yml \
             examples/lpr/frigate.lpr.yml; do
    [ -f "$cfg" ] || continue
    sed -i.bak "s/^  client_id: frigate$/  client_id: $CLIENT_ID/" "$cfg"
    rm -f "${cfg}.bak"
  done

  # Substitute DOCKER_HOST_IP in HA Lovelace dashboard + all example dashboards.
  # Anchored to 'url: http://' prefix so it ONLY touches iframe URLs, not comments.
  for f in config/homeassistant/ui-lovelace.yaml \
           examples/multi-camera/ui-lovelace.yaml \
           examples/multi-spot-single-camera/ui-lovelace.yaml \
           examples/lpr/ui-lovelace.yaml; do
    [ -f "$f" ] || continue
    # Two patterns, both anchored to 'url: http://...:5000':
    #  1. Replace placeholder 'DOCKER_HOST_IP' in URL
    #  2. Replace any existing IP in URL (handles re-runs after IP change)
    sed -i.bak -E \
      -e "s|(url: http://)DOCKER_HOST_IP(:5000)|\1${DOCKER_HOST_IP}\2|g" \
      -e "s|(url: http://)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:5000)|\1${DOCKER_HOST_IP}\2|g" \
      "$f"
    rm -f "${f}.bak"
  done
else
  echo "✓ .env already exists. Checking secrets.yaml sync..."
  # Re-sync secrets.yaml from .env to prevent drift. Detect manual edits via
  # marker comment; warn user before clobbering custom additions.
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a

  if [ -f config/homeassistant/secrets.yaml ] && \
     ! grep -q "^# Auto-generated by setup.sh" config/homeassistant/secrets.yaml; then
    echo "  ⚠ secrets.yaml lacks setup.sh marker — appears manually edited."
    read -r -p "  Overwrite manual edits with .env values? [y/N]: " OVERWRITE
    OVERWRITE_LC=$(echo "$OVERWRITE" | tr '[:upper:]' '[:lower:]')
    if [ "$OVERWRITE_LC" != "y" ]; then
      echo "  → Keeping manual secrets.yaml. .env changes NOT propagated."
    else
      cat > config/homeassistant/secrets.yaml <<EOF
# Auto-generated by setup.sh — re-run setup.sh to regenerate after .env edits
mqtt_user: ${MQTT_USER:-frigate}
mqtt_password: ${MQTT_PASSWORD:-change_this}
whatsapp_phone: "${WHATSAPP_PHONE:-48501234567}"
whatsapp_apikey: "${WHATSAPP_APIKEY:-1234567}"
EOF
      chmod 600 config/homeassistant/secrets.yaml
      echo "  ✓ secrets.yaml regenerated"
    fi
  else
    cat > config/homeassistant/secrets.yaml <<EOF
# Auto-generated by setup.sh — re-run setup.sh to regenerate after .env edits
mqtt_user: ${MQTT_USER:-frigate}
mqtt_password: ${MQTT_PASSWORD:-change_this}
whatsapp_phone: "${WHATSAPP_PHONE:-48501234567}"
whatsapp_apikey: "${WHATSAPP_APIKEY:-1234567}"
EOF
    chmod 600 config/homeassistant/secrets.yaml
    echo "  ✓ secrets.yaml synced from .env"
  fi
  # Load existing values
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a

  # Check for keys added in v1.3.2+
  MISSING_KEYS=()
  [ -z "${TZ:-}" ] && MISSING_KEYS+=("TZ")

  if [ ${#MISSING_KEYS[@]} -gt 0 ]; then
    echo
    echo "⚠ Your .env is missing keys added in newer versions: ${MISSING_KEYS[*]}"
    echo "Please add the following lines to .env, then re-run setup.sh:"
    echo
    for k in "${MISSING_KEYS[@]}"; do
      case "$k" in
        TZ)
          DEFAULT_TZ=$(cat /etc/timezone 2>/dev/null || readlink /etc/localtime 2>/dev/null | sed 's|.*zoneinfo/||' || echo "UTC")
          echo "  TZ=$DEFAULT_TZ"
          ;;
      esac
    done
    echo
    read -r -p "Add these now and proceed? [Y/n]: " ADD_MISSING
    # Lowercase the response — compatible with bash 3.2 (macOS default)
    ADD_MISSING_LC=$(echo "${ADD_MISSING:-y}" | tr '[:upper:]' '[:lower:]')
    if [ "$ADD_MISSING_LC" != "n" ]; then
      for k in "${MISSING_KEYS[@]}"; do
        case "$k" in
          TZ) echo "TZ=$(cat /etc/timezone 2>/dev/null || readlink /etc/localtime 2>/dev/null | sed 's|.*zoneinfo/||' || echo UTC)" >> .env ;;
        esac
      done
      echo "✓ Keys added to .env"
      # Re-source the updated values
      set -a
      # shellcheck disable=SC1091
      source .env
      set +a
    fi
  fi

  # Auto-detect DOCKER_HOST_IP if not done before (for ui-lovelace substitution)
  if grep -q "DOCKER_HOST_IP" config/homeassistant/ui-lovelace.yaml 2>/dev/null; then
    DETECTED_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1.1.1.1 2>/dev/null | awk '/src/ {print $7}')
    if [ -n "$DETECTED_IP" ]; then
      sed -i.bak "s/DOCKER_HOST_IP/$DETECTED_IP/g" config/homeassistant/ui-lovelace.yaml
      rm -f config/homeassistant/ui-lovelace.yaml.bak
      echo "✓ Substituted DOCKER_HOST_IP → $DETECTED_IP in ui-lovelace.yaml"
    fi
  fi
fi

# Ensure env is loaded for both fresh + re-run paths
set -a
# shellcheck disable=SC1091
source .env
set +a

# ─────────────────────────────────────────────────────────────
# 3. Mosquitto password file
# ─────────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════"
echo "  STEP 3: Generate MQTT password"
echo "════════════════════════════════════════════════════"
docker run --rm -v "$PROJ/config:/mosquitto/config" eclipse-mosquitto:2.0 \
  mosquitto_passwd -c -b /mosquitto/config/passwd "$MQTT_USER" "$MQTT_PASSWORD"
# Restrict permissions — file contains hashed passwords
chmod 600 config/passwd
echo "✓ MQTT passwd OK (chmod 600)"

# ─────────────────────────────────────────────────────────────
# 4. Test RTSP stream
# ─────────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════"
echo "  STEP 4: Test RTSP to camera"
echo "════════════════════════════════════════════════════"
RTSP_URL="rtsp://$RTSP_USER:$RTSP_PASSWORD@$CAMERA_IP:554/h264Preview_01_sub"
echo "Test URL: rtsp://$RTSP_USER:***@$CAMERA_IP:554/h264Preview_01_sub"
# Wrap docker run with `timeout` so a hanging RTSP server can't block setup forever
if timeout 30 docker run --rm linuxserver/ffmpeg:latest \
    -rtsp_transport tcp -i "$RTSP_URL" \
    -frames:v 1 -f null - 2>&1 | grep -q "Stream #"; then
  echo "✓ RTSP works"
else
  echo "⚠ RTSP did not respond on h264Preview_01_sub (or timed out after 30s)"
  echo "   Try alternative paths — check config/frigate.yml comments"
  echo "   (h265Preview_01_sub for HEVC, or Preview_01_main for older models)"
fi

# ─────────────────────────────────────────────────────────────
# 5. WhatsApp smoke test
# ─────────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════"
echo "  STEP 5: WhatsApp test"
echo "════════════════════════════════════════════════════"
TEST_MSG="parking-pack setup test — if you see this message, alerts work!"
WA_RESP=$(curl -sk --max-time 30 -G \
  --data-urlencode "phone=$WHATSAPP_PHONE" \
  --data-urlencode "text=$TEST_MSG" \
  --data-urlencode "apikey=$WHATSAPP_APIKEY" \
  "https://api.callmebot.com/whatsapp.php")
if echo "$WA_RESP" | grep -qiE "message queued|sent"; then
  echo "✓ WhatsApp test sent — check phone"
else
  echo "⚠ WhatsApp may not work — CallMeBot response:"
  echo "$WA_RESP" | head -c 500
fi

# ─────────────────────────────────────────────────────────────
# 6. Start stack
# ─────────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════"
echo "  STEP 6: Start Docker stack"
echo "════════════════════════════════════════════════════"
docker compose up -d

echo
echo "════════════════════════════════════════════════════"
echo "✅ DONE!"
echo "════════════════════════════════════════════════════"
echo
echo "  Frigate UI:        http://localhost:5000"
echo "  Home Assistant:    http://localhost:8123"
echo
echo "  Next steps — see README.md (section 'Step 4 — Draw the zone')"
