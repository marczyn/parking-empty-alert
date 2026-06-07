---
name: 🐛 Bug Report
about: Something doesn't work as documented
title: '[Bug] '
labels: bug
assignees: ''
---

## Description

<!-- Clear, concise description of the bug -->

## Steps to reproduce

1. ...
2. ...
3. ...

## Expected behavior

<!-- What should have happened -->

## Actual behavior

<!-- What actually happened -->

## Environment

- **OS:** (e.g., Ubuntu 24.04, Windows 11, macOS 14.5)
- **Docker version:** `docker --version`
- **Docker Compose version:** `docker compose version`
- **Camera model:** (e.g., Reolink RLC-810A)
- **Camera firmware:** (e.g., v3.0.0.494)
- **parking-empty-alert version:** (e.g., v1.0.0 or commit SHA)
- **Frigate image tag:** `stable` or specific
- **Home Assistant image tag:** `stable` or specific

## Logs

<details>
<summary>Frigate logs (<code>docker compose logs frigate | tail -100</code>)</summary>

```
paste here
```

</details>

<details>
<summary>HA logs (<code>docker compose logs homeassistant | tail -100</code>)</summary>

```
paste here
```

</details>

<details>
<summary>Mosquitto logs (<code>docker compose logs mosquitto | tail -50</code>)</summary>

```
paste here
```

</details>

## Configuration

<details>
<summary><code>config/frigate.yml</code> (REDACT credentials!)</summary>

```yaml
paste here, with passwords replaced by <REDACTED>
```

</details>

## Screenshots

<!-- If applicable, drag-and-drop -->

## Have you checked?

- [ ] Tried the [troubleshooting guide](https://github.com/marczyn/parking-empty-alert/blob/main/docs/INSTALLATION.md#11-common-installation-issues)
- [ ] Tried the [user guide troubleshooting](https://github.com/marczyn/parking-empty-alert/blob/main/docs/USER_GUIDE.md#16-troubleshooting)
- [ ] Searched [existing issues](https://github.com/marczyn/parking-empty-alert/issues?q=is%3Aissue)
- [ ] Tested against the latest commit on `main`
