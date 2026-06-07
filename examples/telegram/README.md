# Telegram notification example

Use Telegram bot instead of (or alongside) WhatsApp for parking alerts.

**Advantages over WhatsApp/CallMeBot:**
- ✅ No 1-message-per-minute rate limit
- ✅ Official Telegram Bot API (high reliability, real SLA)
- ✅ Image/video attachments work natively
- ✅ Inline buttons for actions ("Snooze 30 min", "Open camera")
- ✅ Group chats (alert your whole family in one bot)

**Disadvantages:**
- ❌ Recipients need Telegram installed (not universal like WhatsApp)
- ❌ Slightly more setup (BotFather)

## Setup

### Step 1 — Create Telegram bot via BotFather

1. Open Telegram → search **@BotFather**
2. Send `/newbot`
3. Choose display name (e.g., "Parking Alerts")
4. Choose username (must end with `_bot`, e.g., `my_parking_alerts_bot`)
5. BotFather replies with a token: `123456789:ABCdef-GHIjkl_MNOpqr`
   **Save this token** — it's the bot's password

### Step 2 — Get your chat ID

1. Search for your new bot in Telegram → click **Start**
2. Send any message to the bot (e.g., `hi`)
3. Open in browser:
   ```
   https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates
   ```
4. Find `"chat":{"id":<NUMBER>}` in the JSON — that number is your chat ID

For **group chats**: add bot to group, send message, get group chat ID
(starts with `-`).

### Step 3 — Add to HA secrets

Edit `config/homeassistant/secrets.yaml`:

```yaml
# Existing secrets remain
mqtt_user: frigate
mqtt_password: ...
whatsapp_phone: "..."
whatsapp_apikey: "..."

# Add Telegram
telegram_bot_token: "123456789:ABCdef-GHIjkl_MNOpqr"
telegram_chat_id: "-123456789"   # leading minus for group, or positive for DM
```

### Step 4 — Add to HA configuration

Append `examples/telegram/configuration.yaml` snippet to your
`config/homeassistant/configuration.yaml`:

```bash
cat examples/telegram/configuration.yaml >> config/homeassistant/configuration.yaml
```

This adds:
- `telegram_bot:` (the underlying Telegram client)
- `notify:` entry named `telegram_parking`

### Step 5 — Switch automation to Telegram

Edit `config/homeassistant/automations.yaml`, replace:
```yaml
- service: notify.whatsapp_parking
```
with:
```yaml
- service: notify.telegram_parking
```

(Or keep BOTH for redundant alerts — Telegram + WhatsApp.)

### Step 6 — Restart HA

```bash
docker compose restart homeassistant
```

## Test

HA UI → Developer Tools → Services → `notify.telegram_parking` → message: "test"
→ Send. Telegram message should arrive in <1 sec.

## Sending images / video

Telegram bot supports attachments — modify your automation:

```yaml
action:
  - service: notify.telegram_parking
    data:
      message: "🅿️ Spot free!"
      data:
        photo:
          # Snapshot from Frigate
          url: "http://DOCKER_HOST_IP:5000/api/parking/latest.jpg?h=300"
        # Or inline keyboard:
        keyboard:
          - "/snooze_30, /snooze_60"
          - "/open_camera"
```

## Rate limits

Telegram Bot API limits:
- 30 messages per second per bot (way more than parking needs)
- 20 messages per minute per group
- No per-user limit for direct messages

For comparison, CallMeBot WhatsApp = 1 message per minute.

## Multiple recipients

**Option 1 — Group chat:** add bot to a Telegram group, use group chat_id.
Everyone in the group gets the alert.

**Option 2 — Multiple services:** define `notify.telegram_jan` and
`notify.telegram_anna` with different chat_ids, call both in automation.
