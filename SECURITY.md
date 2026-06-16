# Security

## Never commit

- `.env` files
- API keys or access tokens
- Tailscale authentication keys
- SSH private keys
- backup passphrases or recovery keys
- database dumps
- decrypted backup contents
- `/etc/rancher/k3s` certificates and tokens
- live `k3s.yaml` files containing real server addresses
- personal IP addresses unless intentionally disclosed

## Public-repository rule

This repository is designed to be safe to publish. It uses placeholders and examples rather than live credentials.

Before every push:

```bash
git status --short
git diff --cached
git grep -nEi \
  '(password|passwd|secret|token|api[_-]?key|BEGIN .*PRIVATE KEY|100\.[0-9]+\.[0-9]+\.[0-9]+)' \
  -- ':!SECURITY.md' ':!docs/*'
```

Review every match manually.

## Host hardening

- Keep UFW default-deny inbound.
- Permit SSH only from a trusted LAN CIDR and `tailscale0`.
- Keep Ollama bound to loopback unless there is a deliberate authenticated proxy.
- Avoid router port forwarding to the lab.
- Keep recovery keys off the server.
- Apply security updates regularly.
- Treat Docker-published ports carefully because Docker networking can interact with firewall policy in ways that differ from ordinary host services.

## Reporting

This is a personal lab repository. Open a private security report through GitHub if a committed secret or unsafe default is discovered.
