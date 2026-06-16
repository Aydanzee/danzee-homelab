# Changelog

## Unreleased

- Made Portainer and Uptime Kuma volume snapshots consistent by stopping and reliably restarting their containers.
- Added filesystem-specific USB mount options and explicit supported-filesystem checks.
- Pinned the tested k3s and Ollama versions in the example configuration.
- Replaced the Tailscale curl-to-shell path with its official Ubuntu stable apt repository.
- Added the k3s pod and service network UFW allowances used by the working host.
- Added GitHub Actions validation for Bash, YAML and sensitive filenames.
- Corrected the systemd documentation URL and expanded the tested-environment documentation.

## 2026-06-16

- Documented the initial Ubuntu homelab build.
- Added Docker Compose stack for MariaDB, Portainer, and Uptime Kuma.
- Added single-node k3s lab manifests and resource guardrails.
- Added Tailscale and UFW access model.
- Added low-memory Ollama configuration.
- Added encrypted USB backup automation, retention, and restore validation.
- Added Mac-side GitHub publishing helper.
