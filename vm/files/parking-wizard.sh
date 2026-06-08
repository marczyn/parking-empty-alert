#!/bin/bash
# First-boot configuration wizard for parking-empty-alert.
# Runs on tty1 before getty. Prompts for required env vars, pulls the Docker
# image, starts the parking service, then hands tty1 back to getty.
set -euo pipefail

ENV_FILE="/etc/parking.env"
SENTINEL="/var/lib/parking/.configured"
VARIANT_FILE="/etc/parking-variant"

# Already configured — nothing to do
if [ -f "$SENTINEL" ]; then
    exit 0
fi

# Read variant info
source "$VARIANT_FILE"

# ── Helpers ────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

ask() {
    local prompt="$1" varname="$2" default="${3:-}" secret="${4:-no}"
    while true; do
        if [ -n "$default" ]; then
            printf "${CYAN}%s${RESET} [%s]: " "$prompt" "$default"
        else
            printf "${CYAN}%s${RESET}: " "$prompt"
        fi
        if [ "$secret" = "yes" ]; then
            read -r -s value; echo
        else
            read -r value
        fi
        value="${value:-$default}"
        if [ -n "$value" ]; then
            eval "$varname='$value'"
            return 0
        fi
        printf "${RED}Required — cannot be empty.${RESET}\n"
    done
}

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS='.'; read -ra parts <<< "$ip"
        for part in "${parts[@]}"; do
            (( part <= 255 )) || return 1
        done
        return 0
    fi
    return 1
}

# ── Check for pre-populated env file (cloud-init / automated deploy) ──────────
if [ -f "$ENV_FILE" ]; then
    echo ""
    printf "${GREEN}[parking]${RESET} Configuration found at %s — skipping wizard.\n" "$ENV_FILE"
    systemctl enable parking.service 2>/dev/null || true
    systemctl start  parking.service 2>/dev/null || true
    mkdir -p /var/lib/parking
    touch "$SENTINEL"
    exit 0
fi

# ── Banner ─────────────────────────────────────────────────────────────────────
clear
printf "${BOLD}${CYAN}"
cat <<'BANNER'
  ____            _    _                ____  _           _
 |  _ \ __ _ _ __| | _(_)_ __   __ _  |  _ \| | ___ _ __| |_
 | |_) / _` | '__| |/ / | '_ \ / _` | | |_) | |/ _ \ '__| __|
 |  __/ (_| | |  |   <| | | | | (_| | |  __/| |  __/ |  | |_
 |_|   \__,_|_|  |_|\_\_|_| |_|\__, | |_|   |_|\___|_|   \__|
                                 |___/
BANNER
printf "${RESET}"
printf "${BOLD}  parking-empty-alert — First Boot Setup${RESET}\n"
printf "  Image: ${CYAN}%s${RESET}\n\n" "$IMAGE_NAME"
printf "  This wizard configures your camera and notification settings.\n"
printf "  Values are saved to %s and can be changed later.\n\n" "$ENV_FILE"
printf "  Press ${BOLD}Enter${RESET} to accept a default shown in [brackets].\n"
printf "  ${YELLOW}─────────────────────────────────────────────────────────${RESET}\n\n"

# ── Camera ─────────────────────────────────────────────────────────────────────
printf "${BOLD}Camera${RESET}\n\n"

while true; do
    ask "Camera IP address (e.g. 192.168.1.100)" CAMERA_IP
    if validate_ip "$CAMERA_IP"; then break; fi
    printf "${RED}Not a valid IP address. Try again.${RESET}\n"
done

ask "RTSP username" RTSP_USER "frigate"
ask "RTSP password" RTSP_PASSWORD "" "yes"

# ── Notifications ──────────────────────────────────────────────────────────────
printf "\n${BOLD}WhatsApp notifications (CallMeBot)${RESET}\n"
printf "  Get your API key: send ${CYAN}I allow callmebot to send me messages${RESET}\n"
printf "  to WhatsApp contact ${CYAN}+34 644 11 11 11${RESET}, wait ~2 min for reply.\n\n"

if [ "$VARIANT" = "full" ]; then
    while true; do
        ask "Your WhatsApp number with country code (e.g. 48501234567)" WHATSAPP_PHONE
        [[ "$WHATSAPP_PHONE" =~ ^[0-9]{8,15}$ ]] && break
        printf "${RED}Use digits only, no + or spaces.${RESET}\n"
    done
    ask "CallMeBot API key (7 digits from reply message)" WHATSAPP_APIKEY
fi

# ── Confirm ────────────────────────────────────────────────────────────────────
printf "\n${YELLOW}─────────────────────────────────────────────────────────${RESET}\n"
printf "${BOLD}Summary${RESET}\n\n"
printf "  Camera IP  : %s\n" "$CAMERA_IP"
printf "  RTSP user  : %s\n" "$RTSP_USER"
printf "  RTSP pass  : %s\n" "$(echo "$RTSP_PASSWORD" | sed 's/./*/g')"
if [ "$VARIANT" = "full" ]; then
    printf "  WhatsApp   : +%s\n" "$WHATSAPP_PHONE"
    printf "  API key    : %s\n" "$WHATSAPP_APIKEY"
fi
printf "\n"

read -r -p "Proceed? [Y/n] " CONFIRM
CONFIRM="${CONFIRM:-y}"
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    printf "${YELLOW}Aborted. Reboot to run the wizard again.${RESET}\n"
    exit 1
fi

# ── Write env file ─────────────────────────────────────────────────────────────
printf "\n${BOLD}Writing configuration...${RESET}\n"

cat > "$ENV_FILE" <<EOF
FRIGATE_CAMERA_IP=${CAMERA_IP}
FRIGATE_RTSP_USER=${RTSP_USER}
FRIGATE_RTSP_PASSWORD=${RTSP_PASSWORD}
EOF

if [ "$VARIANT" = "full" ]; then
    cat >> "$ENV_FILE" <<EOF
WHATSAPP_PHONE=${WHATSAPP_PHONE}
WHATSAPP_APIKEY=${WHATSAPP_APIKEY}
EOF
fi

chmod 600 "$ENV_FILE"

# ── Pull Docker image ──────────────────────────────────────────────────────────
printf "${BOLD}Pulling Docker image (first run — may take several minutes)...${RESET}\n\n"
docker pull "$IMAGE_NAME" 2>&1 | grep -E 'Pulling|Pull complete|Digest|Status' || true

# ── Start service ──────────────────────────────────────────────────────────────
printf "\n${BOLD}Starting parking service...${RESET}\n"
systemctl enable parking.service
systemctl start  parking.service

mkdir -p /var/lib/parking
touch "$SENTINEL"

# ── Done ───────────────────────────────────────────────────────────────────────
HOST_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "<this-machine-ip>")

printf "\n${GREEN}${BOLD}Setup complete!${RESET}\n\n"
printf "  ${BOLD}Frigate UI     :${RESET} ${CYAN}http://%s:8090${RESET}\n" "$HOST_IP"
if [ "$VARIANT" = "full" ]; then
    printf "  ${BOLD}Home Assistant :${RESET} ${CYAN}http://%s:8123${RESET}\n" "$HOST_IP"
fi
printf "  ${BOLD}MQTT broker    :${RESET} %s:1883\n\n" "$HOST_IP"
printf "  Configuration : %s\n" "$ENV_FILE"
printf "  Logs          : journalctl -u parking\n\n"
printf "  ${YELLOW}Draw your parking zone in Frigate UI → camera → Edit Zones.${RESET}\n\n"

printf "  Press Enter to continue to login prompt...\n"
read -r _
