# Changelog

## 1.1.0 - 2026-06-17

- Added lightweight Beszel host and Docker resource monitoring with historical charts.
- Added a loopback-only Docker socket proxy and root-only Beszel agent credentials.
- Added LAN- and Tailscale-scoped firewall access for the Beszel dashboard.
- Added reusable Beszel installation, agent-setup, rollback, and health-check automation.
- Documented Axiom Local v1.2 persistent chats, file uploads, model warm retention, and long-answer continuation.
- Documented the distinction between availability monitoring, resource monitoring, and whole-network traffic accounting.
- Recorded Beszel database backup integration as a follow-up requiring a tested consistent snapshot.

## 1.0.0 - 2026-06-17

- Made Portainer and Uptime Kuma volume snapshots consistent by stopping and reliably restarting their containers.
- Added filesystem-specific USB mount options and explicit supported-filesystem checks.
- Pinned the tested k3s and Ollama versions in the example configuration.
- Replaced the Tailscale curl-to-shell path with its official Ubuntu stable apt repository.
- Added the k3s pod and service network UFW allowances used by the working host.
- Added GitHub Actions validation for Bash, YAML and sensitive filenames.
- Added Uptime Kuma monitoring for Axiom Local, the k3s demo workload, Portainer, and nightly encrypted backups.
- Added a successful-backup Push heartbeat with retry handling after the Uptime Kuma volume snapshot.
- Added reproducible monitoring automation, runbook guidance, and scoped Docker-subnet firewall rules.
- Corrected the systemd documentation URL and expanded the tested-environment documentation.

## 2026-06-16

- Documented the initial Ubuntu homelab build.
- Added Docker Compose stack for MariaDB, Portainer, and Uptime Kuma.
- Added single-node k3s lab manifests and resource guardrails.
- Added Tailscale and UFW access model.
- Added low-memory Ollama configuration.
- Added encrypted USB backup automation, retention, and restore validation.
- Added Mac-side GitHub publishing helper.
