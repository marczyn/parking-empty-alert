# Contributing to Parking Empty Alert

Thanks for considering a contribution! This guide explains how to file good issues, submit pull requests, and run the test suite locally.

## Quick links

- 🐛 [Report a bug](https://github.com/marczyn/parking-empty-alert/issues/new?template=bug_report.md)
- 💡 [Request a feature](https://github.com/marczyn/parking-empty-alert/issues/new?template=feature_request.md)
- 🔒 [Report a security vulnerability](SECURITY.md)
- 📖 [Documentation](docs/)

## Ground rules

1. **Be respectful.** No personal attacks, no spam, no offensive language.
2. **One concern per issue/PR.** Bug fixes, features, refactors — keep them separate.
3. **Test your changes** locally before opening a PR.
4. **Update docs** when you change behavior. Out-of-sync docs are a bug.
5. **All code, comments, commit messages: English.**

## How to contribute

### Reporting bugs

Before filing an issue:
1. Search [existing issues](https://github.com/marczyn/parking-empty-alert/issues) — your bug may already be reported.
2. Try the [troubleshooting guide](docs/INSTALLATION.md#11-common-installation-issues) and [user guide](docs/USER_GUIDE.md#16-troubleshooting).
3. Test against the **latest commit on main**.

When filing a new bug, use the template — it asks for:
- Steps to reproduce
- Expected vs actual behavior
- Camera model and HA / Frigate / Docker versions
- Relevant logs

### Suggesting features

Use the feature request template. State:
- The use case (what problem does this solve?)
- The proposed solution (or "I don't know how, but I'd like X")
- Alternatives considered

Maintainers may close the issue with a recommendation to keep it forked, if the feature is too niche.

### Submitting a pull request

```bash
# 1. Fork the repo on GitHub
# 2. Clone your fork
git clone https://github.com/<your-username>/parking-empty-alert.git
cd parking-empty-alert

# 3. Install pre-commit hook (REQUIRED — blocks accidental secret leaks)
bash scripts/install-git-hooks.sh

# 4. Create a topic branch
git checkout -b feat/your-feature-name

# 5. Make your changes
# 6. Validate locally
docker compose config --quiet                    # check compose YAML
python -c "import yaml; yaml.safe_load(open('config/frigate.yml'))"  # check frigate YAML
shellcheck --severity=warning scripts/*.sh       # check shell scripts

# 7. Commit (see commit message style below)
git commit -m "feat: short summary of change"
# (pre-commit hook will validate no secrets are committed)

# 8. Push and open PR
git push origin feat/your-feature-name
# Then open PR on GitHub
```

### Commit message style

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <short summary>

<body — optional, longer explanation>

<footer — optional, e.g. "Fixes #123">
```

Types:
- `feat:` — new feature
- `fix:` — bug fix
- `docs:` — documentation only
- `chore:` — no functional change (formatting, deps, build)
- `refactor:` — code change without behavior change
- `test:` — adding or fixing tests
- `ci:` — CI workflow change

Example:
```
feat: add Telegram notification fallback

When CallMeBot is down, fallback to Telegram bot.
Configured via TELEGRAM_TOKEN in .env.

Fixes #42
```

### Pull request checklist

Before requesting review, verify:
- [ ] CI is green (yamllint, compose validate, shellcheck, frigate config schema)
- [ ] Behavior matches what the PR description says
- [ ] README / docs updated for any new feature
- [ ] No secrets committed (run `git diff --cached` to verify)
- [ ] One topic per PR (split unrelated changes into separate PRs)

## Project structure

```
parking-empty-alert/
├── docker-compose.yml           # main compose (Linux)
├── docker-compose.macwin.yml    # override for Docker Desktop
├── .env.example                 # secrets template
├── config/
│   ├── frigate.yml              # Frigate NVR config
│   ├── mosquitto.conf           # MQTT broker config
│   └── homeassistant/           # HA configs
├── scripts/setup.sh             # interactive installer
├── examples/multi-camera/       # 3-camera example
├── docs/                        # detailed guides
└── .github/
    ├── workflows/ci.yml         # CI pipeline
    ├── ISSUE_TEMPLATE/
    └── PULL_REQUEST_TEMPLATE.md
```

## Running CI locally

```bash
# YAML lint
pip install yamllint
yamllint docker-compose.yml config/frigate.yml config/homeassistant/*.yaml

# Compose validation
cp .env.example .env
docker compose config --quiet

# Shellcheck
shellcheck scripts/setup.sh

# Frigate config schema
docker pull ghcr.io/blakeblackshear/frigate:stable
docker run --rm -v "$PWD/config/frigate.yml:/config/config.yml:ro" \
  --entrypoint python3 ghcr.io/blakeblackshear/frigate:stable \
  -c "import yaml; yaml.safe_load(open('/config/config.yml'))"
```

## Code review process

- Maintainer reviews within 5 business days
- We may request changes (don't take it personally)
- Once approved, maintainer merges (with squash or rebase)
- Your contribution will appear in the next release

## Roadmap (high-level)

See [issues with the `roadmap` label](https://github.com/marczyn/parking-empty-alert/labels/roadmap).

Current priorities (sorted):
1. License plate recognition (LPR) for owner-specific alerts
2. Multi-spot single-camera support (wide-angle camera, 5 spots)
3. Grafana dashboards for occupancy analytics
4. Non-Reolink camera templates (Hikvision, Dahua, generic ONVIF)
5. NAS deployment guides (Synology, UnRAID, QNAP)

## License

By contributing, you agree your contributions are licensed under the [MIT License](LICENSE).
