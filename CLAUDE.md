# parking-empty-alert — Engineering Guide

> Operational guide for working on this repo. Hard rules + hard-won gotchas.
> This is infrastructure-as-code (no application code / unit tests) — Frigate +
> MQTT + Home Assistant for parking-spot-empty detection, shipped two ways.

---

## What this is

A self-hosted stack that watches a parking spot with a camera and sends a
WhatsApp alert (via CallMeBot) when it becomes free. Two delivery formats:

1. **Compose stack** (`docker-compose.yml`) — mosquitto + frigate + home-assistant
   as separate containers. `docker-compose.macwin.yml` is the Docker Desktop override.
2. **All-in-one images** (`Dockerfile.aio-{full,lite}`) — single s6-overlay container
   built on the Frigate base image. **full** = Frigate + Mosquitto + Home Assistant;
   **lite** = Frigate + Mosquitto (connect your *existing* HA).
3. **VM/OVA appliance** — `vm/parking.pkr.hcl` (Packer) builds a Debian OVA whose
   first-boot wizard (`vm/files/parking-wizard.sh`) configures + runs the AIO image.

`scripts/setup.sh` is the interactive installer for the compose stack.

---

## GIT / CI GOVERNANCE (hard rules)

- **NEVER commit directly to `main`** — feature branch → PR → squash-merge.
- **NEVER bypass branch protection** (`--admin`, force-push to main, skipping checks).
  Merge ONLY after required CI is green **and** the user has authorized that PR.
- Required checks (`.github/workflows/ci.yml`): `Validate configs`, `ShellCheck scripts`,
  `Frigate config schema validation`, `Lint GitHub workflows` (actionlint).
- CI runs on a **single self-hosted runner** (`[self-hosted, linux, x64, parking]`,
  host `192.168.2.180`). It is the throughput bottleneck — release builds (images +
  OVA, slow emulated arm64) serialize ahead of PR CI. If a required check sits in
  `QUEUED` forever, the runner is offline — start it, don't bypass.
- All self-hosted jobs are gated with
  `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`
  so untrusted fork-PR code never runs on the persistent runner (it also publishes
  images / builds OVAs). Keep this guard on any new self-hosted job.

---

## GOTCHAS (these have all bitten — do not relearn the hard way)

1. **s6 does NOT pass the container env to `cont-init.d` scripts.** Any AIO
   cont-init or s6 `run` script that reads a `-e` runtime var (e.g.
   `FRIGATE_RTSP_PASSWORD`, `FRIGATE_MQTT_*`) MUST use the shebang
   `#!/command/with-contenv sh`. With plain `#!/bin/sh` the vars are unset →
   a fail-fast aborts boot and substitutions silently use placeholders.
2. **Literal `${{ }}` inside a `run:` block is a fatal workflow parse error.**
   GitHub evaluates `${{ }}` anywhere in a run script; an empty/placeholder one
   disables the whole workflow (shows as "workflow file issue" on push). PyYAML
   accepts it — that's why the `actionlint` CI job exists. Never write `${{ }}`
   in a `run:` comment; keep such notes in YAML-level comments.
3. **CRLF breaks heredoc shebangs in local Windows builds.** The Dockerfiles bake
   s6 `run`/cont-init scripts via heredocs; a CRLF Dockerfile yields `#!/bin/sh\r`
   and s6 can't spawn the script. `.gitattributes` keeps everything LF in git
   (so CI/release builds are fine), but when building locally on Windows, build
   from an LF-normalized copy (`sed 's/\r$//' Dockerfile.aio-lite > x && docker build -f x .`).
4. **AIO env var names are `FRIGATE_*`** (`FRIGATE_CAMERA_IP`, `FRIGATE_RTSP_USER`,
   `FRIGATE_RTSP_PASSWORD`, `FRIGATE_MQTT_USER/PASSWORD`) plus `WHATSAPP_PHONE/APIKEY`.
   The compose stack's `.env` uses non-prefixed names (`RTSP_USER`, …) which compose
   maps to `FRIGATE_*` inside the container. Don't mix them in docs/run commands.
5. **full vs lite broker model differ by design.** full = broker localhost-only,
   anonymous (Frigate + in-container HA reach it over localhost; 1883 NOT published).
   lite = broker authenticated + published on 1883 (your *external* HA connects, so
   it must be reachable; passwd generated at start from `FRIGATE_MQTT_USER/PASSWORD`,
   chowned to the `mosquitto` user since mosquitto drops privileges before reading it).
6. **Host-network HA can't resolve the Docker name `mosquitto`.** On the compose
   Linux path HA uses `network_mode: host`, so its MQTT broker host comes from the
   `MQTT_BROKER` env var (default `127.0.0.1` = the loopback-published broker); the
   macwin override sets `host.docker.internal`.
7. **OVA `attach-to-release` only runs on the `release` event**, not `workflow_dispatch`.
   A dispatched OVA build produces artifacts, not release assets — attach them with
   `gh release upload` (or re-cut the release, which also re-runs docker-publish).
8. **`setup.sh` never `source`s `.env`.** Use the `load_env()` literal reader
   (it strips CR and quotes, never shell-evaluates). `.env` values are single-quoted;
   RTSP user/pass reject single quotes. Keep `.env` `0600`.
9. **Validate workflows with actionlint, not just PyYAML.** The `Validate configs`
   job parses YAML; it accepts files GitHub's stricter Actions parser rejects.

---

## SUPPLY CHAIN

- All container images are pinned to `@sha256` digests (compose + both Dockerfiles).
- All GitHub Actions are pinned to full commit SHAs (version in a trailing `# vX` comment).
- The VM/OVA pins the app image to the immutable `:v<version>` tag (not `:latest`).
- docker-publish tags each per-arch child with an immutable `:<release>-amd64/-arm64`
  tag so the untagged-version cleanup can't delete the platform children an older
  `:v<release>` manifest list (and OVA pin) depends on.
- Digest pins mean `docker compose pull` will NOT auto-update — bump digests
  deliberately (see the `docker-compose.yml` header refresh command).
- `dependabot.yml` groups action/image bumps; major HA/Frigate jumps go to manual review.

---

## SECURITY INVARIANTS

- No real secrets in the repo. AIO images ship **no** baked secret defaults — required
  secrets fail fast at boot. `.env`, `config/passwd`, `secrets.yaml` are gitignored
  and `0600`; the pre-commit hook (scan the **staged blob**, per-field template
  assertion, anchored leak filters) blocks accidental commits.
- Frigate UI (8090) auth is **disabled by design** on the AIO images (trusted-LAN
  appliance) — never publish 8090/8123 to an untrusted network. HA login has
  `ip_ban_enabled` + `login_attempts_threshold`.
- `restore.sh` rejects absolute / `..` / symlink-and-hardlink tar members before
  extracting a (semi-trusted, possibly off-host) backup.

---

## REVIEW HISTORY — 5 adversarial rounds + release 1.1.0

Five rounds of multi-agent adversarial review (6 per-subsystem finders →
independent refuter per finding, default `isReal=false`). Each round also audited
the previous round's fixes — most round-3/4 findings were regressions in earlier fixes.

| Round | PR | Confirmed | Theme |
|---|---|---|---|
| 1 | #8 | — | baseline hardening (mosquitto bind, HA privileged, CI injection) |
| supply-chain | #10 | — | pin images `@sha256` + Actions to SHAs |
| 2 | #11 | **25** (1 Crit, 5 High, 3 Med, …) | fork-PR RCE guard, `.env` injection, build-vm injection, AIO secret defaults, watchdog, etc. |
| 3 | #13 | **10** (6 regressions) | host-net HA couldn't reach MQTT (whole pipeline dead), recovered-watchdog `for:`, CRLF `.env`, LPR `bus`, anchored leak filters, multi-arch cleanup |
| 4 | #14 | **2** | restore.sh symlink members, wizard sustained-liveness gate |
| 5 | — | **0** | clean — loop converged (25 → 10 → 2 → 0) |

**Then (PR #15, #16, release v1.1.0):** reconciled docs/Dockerfiles with the
hardening and — by *actually building and running both AIO images* — found two
defects that static review + CI missed:
- the **full image was unbootable on `main`** (gotcha #1, the round-2 fail-fast
  ran without env), and
- **`build-vm.yml` had not parsed since round-2** (gotcha #2), so the OVA workflow
  was silently disabled.
Both fixed, `actionlint` added as a CI gate, and **v1.1.0** cut (images published +
both OVAs attached).

**Lesson:** for image/infra changes, static validation (PyYAML, even N review
rounds) is not enough — build and run the artifact. The two worst bugs of the whole
effort were only visible at `docker build` / `docker run` / GitHub's workflow parser.
