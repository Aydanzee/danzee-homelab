#!/usr/bin/env bash
set -Eeuo pipefail

say() {
  printf '\n\033[1;36m==> %s\033[0m\n' "$*"
}

ok=0
warn=0

check_service() {
  local service="$1"
  if systemctl is-active --quiet "$service"; then
    printf 'OK   %-30s active\n' "$service"
    ((ok+=1))
  else
    printf 'WARN %-30s not active\n' "$service"
    ((warn+=1))
  fi
}

say "Host"
hostnamectl --static
uptime
free -h
df -hT /

say "Core services"
for svc in docker k3s ollama tailscaled; do
  check_service "$svc"
done

say "Docker"
if command -v docker >/dev/null 2>&1; then
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
else
  echo "WARN docker command not found"
  ((warn+=1))
fi

say "k3s"
if command -v k3s >/dev/null 2>&1; then
  k3s kubectl get nodes -o wide
  k3s kubectl get pods -A -o wide
else
  echo "WARN k3s command not found"
  ((warn+=1))
fi

say "Tailscale"
if command -v tailscale >/dev/null 2>&1; then
  tailscale status || true
else
  echo "WARN tailscale command not found"
  ((warn+=1))
fi

say "Ollama"
if curl -fsS --max-time 5 http://127.0.0.1:11434/api/tags >/dev/null; then
  echo "OK   Ollama API"
  ((ok+=1))
else
  echo "WARN Ollama API unavailable"
  ((warn+=1))
fi

say "Firewall"
ufw status verbose || true

say "Backup timer"
systemctl list-timers danzee-homelab-backup.timer --all || true

say "Summary"
printf 'Passed checks: %d\nWarnings:      %d\n' "$ok" "$warn"

if (( warn > 0 )); then
  exit 1
fi
