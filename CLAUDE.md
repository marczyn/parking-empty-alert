# parking-empty-alert — Engineering Guide

Infra-as-code: Frigate + MQTT + Home Assistant parking-spot-free alerts.
Delivered as a compose stack, AIO Docker images (`Dockerfile.aio-{full,lite}`), and a Packer OVA.

## Governance
- Never commit to `main`; branch → PR → squash. Never bypass branch protection (`--admin`). Merge only after required CI is green + user OK.
- CI runs on one self-hosted runner (`parking`, 192.168.2.180) — the bottleneck; checks stuck in QUEUED = runner offline.
- Self-hosted jobs gate fork PRs: `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`.

## Gotchas
- AIO cont-init / s6 `run` scripts reading `-e` env MUST use `#!/command/with-contenv sh` (s6 doesn't pass env by default).
- Never put a literal `${{ }}` in a `run:` block — fatal workflow parse error; the actionlint CI job catches it.
- On Windows, build AIO images from LF source (CRLF breaks heredoc shebangs); `.gitattributes` keeps git LF.
- AIO env vars are `FRIGATE_*` (camera/rtsp/mqtt) + `WHATSAPP_*`; compose `.env` uses non-prefixed names.
- full broker: localhost-only, anonymous, 1883 not published. lite broker: authenticated, published 1883 (passwd from `FRIGATE_MQTT_USER/PASSWORD`, chowned to `mosquitto`).
- Host-net HA can't resolve `mosquitto` → broker host via `MQTT_BROKER` env (default `127.0.0.1`).
- OVA/qcow2 are NOT GitHub release assets (each 4.6–11 GB, over the 2 GiB cap). `build-vm.yml` is `workflow_dispatch`-only (no `release` trigger / no attach job); distribute via the GHCR images + on-demand build (see `docs/APPLIANCE.md`).
- `setup.sh` never `source`s `.env` (use `load_env()`); keep `.env` `0600`.

## Supply chain / security
- Images pinned `@sha256`, Actions @SHA, OVA app image `:v<version>`.
- No baked secrets in AIO images (fail-fast). `.env`/`passwd`/`secrets.yaml` gitignored + `0600`; pre-commit hook guards.
- Frigate UI (8090) auth off by design (LAN-only) — never expose.

## Review history
5 adversarial review rounds (25 → 10 → 2 → 0 confirmed) + release 1.1.0. The two worst bugs (full image unbootable; `build-vm.yml` parse error) surfaced only by building/running the artifacts — for image/infra changes, build and run; don't trust static checks alone.
