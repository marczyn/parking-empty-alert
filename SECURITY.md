# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.1.x   | ✅ Yes     |
| 1.0.x   | ✅ Yes     |
| < 1.0   | ❌ No (pre-release) |

Only the latest `main` branch and the latest tagged release receive security updates.

## Reporting a Vulnerability

**Do not** open a public issue for security vulnerabilities.

Instead, please report security vulnerabilities to:
**Email:** marczyn@gmail.com

Include:
- A description of the vulnerability
- Steps to reproduce
- Affected versions/components
- Any proof-of-concept code (private gist preferred)
- Your name/handle for credit (optional)

### What to expect

| Time | Action |
|---|---|
| Within 48 hours | Acknowledgment of report |
| Within 7 days | Initial assessment + severity classification |
| Within 30 days | Patch released or detailed roadmap |
| Coordinated disclosure | Public advisory + CVE (if applicable) |

### What's in scope

- The Docker stack configuration (`docker-compose.yml`, configs)
- The setup script (`scripts/setup.sh`)
- Documentation that could mislead users into insecure configurations

### What's NOT in scope

- Vulnerabilities in upstream projects (Frigate, Home Assistant, Mosquitto, FFmpeg, YOLOv8) — report directly to those projects
- Issues requiring physical access to the Docker host
- DoS attacks against the user's own infrastructure
- Theoretical issues without practical impact

## Security Best Practices for Users

### Required for production

- ✅ Set strong, unique passwords for the Reolink `frigate` user (don't reuse your admin password)
- ✅ Use static IPs for the camera (prevents hijacking via DHCP poisoning)
- ✅ Run on a trusted local network — **never expose ports 5000/8090 (Frigate), 8123 (Home Assistant), 1883 (MQTT) to the internet directly.** Note: the all-in-one images serve the Frigate UI on **8090 with authentication disabled**, so anyone who can reach that port gets unauthenticated access to the camera feeds — keep it LAN-only (and ideally behind a reverse proxy with auth)
- ✅ Keep host OS and Docker daemon up to date
- ✅ Set `chmod 600 .env` to prevent other host users from reading credentials
- ✅ Use a dedicated Linux user for Docker (don't run as root in production)

### Recommended

- 🔒 Enable HTTPS for Home Assistant (via reverse proxy with Let's Encrypt)
- 🔒 Use VPN (WireGuard, Tailscale) or Home Assistant Cloud (Nabu Casa) for remote access
- 🔒 Enable MQTT TLS (modify `mosquitto.conf` to use port 8883 with certs)
- 🔒 Container images are pinned to immutable `@sha256` digests for supply-chain safety, so `docker compose pull` will **not** auto-update them. Review upstream (Frigate/HA/Mosquitto) security advisories and deliberately bump the digest in `docker-compose.yml` (and the `Dockerfile.aio-*` `FROM` lines) when patches land — see the refresh command in the `docker-compose.yml` header. GitHub Actions are likewise pinned to full commit SHAs in `.github/workflows/`.
- 🔒 Subscribe to Frigate and HA security advisories
- 🔒 Set up an isolated VLAN for cameras (cameras can't reach internet or LAN)

### Privacy

This project sends WhatsApp messages via CallMeBot. Message **content** (the alert text) leaves your local network. Video, images, and detection metadata stay local on the Docker host.

See [User Guide §14 — Privacy and security](docs/USER_GUIDE.md#14-privacy-and-security) for full data-flow analysis.

## Known Limitations

- The default `mosquitto.conf` uses password authentication but **no TLS**. MQTT traffic is plaintext on the local network. Acceptable for trusted LAN; not acceptable on shared/public networks.
- The default Home Assistant has **no SSL** on port 8123. Acceptable for LAN-only access; not acceptable for direct internet exposure.
- The `network_mode: host` for Home Assistant grants HA access to all host network interfaces. Acceptable for dedicated Docker hosts; review if running multi-tenant.
- CallMeBot is a 3rd-party service. We have no control over their security posture. If high-confidentiality alerts are required, switch to a self-hosted alternative (Telegram bot you control, Pushover paid plan, or HA Companion local push).

## Credits

We thank the following for reporting vulnerabilities responsibly:
- (None yet — be the first!)
