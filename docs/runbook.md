# Operations runbook

## After a power outage

```bash
systemctl --failed
systemctl status docker k3s ollama tailscaled --no-pager
docker ps
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
systemctl list-timers danzee-homelab-backup.timer --all
```

Because the backup timer uses `Persistent=true`, a missed scheduled run should execute after the machine returns.

## Private app is unavailable

```bash
docker ps --filter name=axiom-local
docker logs --tail 100 axiom-local
curl http://127.0.0.1:8088/api/health
curl http://LAN_IP:8088/api/health
sudo ufw status numbered
```

Then verify Ollama:

```bash
systemctl status ollama --no-pager
curl http://127.0.0.1:11434/api/tags
ollama list
```

## Remote SSH fails

On the client:

```bash
tailscale status
tailscale ping LAB_TAILSCALE_IP
ssh -vvv your-linux-user@LAB_TAILSCALE_IP
```

On the server through LAN or console:

```bash
tailscale status
sudo systemctl status tailscaled --no-pager
sudo ufw status numbered
sudo ss -lntp | grep ':22'
```

## Docker service fails

```bash
systemctl status docker --no-pager
sudo journalctl -u docker -n 150 --no-pager
docker ps -a
docker compose -f /opt/homelab/compose.yaml config
```

## k3s service fails

```bash
systemctl status k3s --no-pager
sudo journalctl -u k3s -n 200 --no-pager
sudo k3s kubectl get events -A --sort-by=.lastTimestamp
```

## Backup job fails

```bash
systemctl status danzee-homelab-backup.service --no-pager
sudo journalctl -u danzee-homelab-backup.service -n 150 --no-pager
findmnt /mnt/danzee-backup
df -hT /mnt/danzee-backup
sudo test -r /root/.config/danzee-backup/backup.passphrase
```

The backup script refuses to write if the mounted partition UUID does not match its configuration.

## Uptime Kuma cannot reach a host service

Confirm the target is healthy from the host first:

```bash
curl -fsS http://127.0.0.1:8088/api/health
```

Then identify the Uptime Kuma Docker network and review the scoped firewall rules:

```bash
docker inspect uptime-kuma
docker network inspect danzee-homelab_default
sudo ufw status numbered
```

Re-run the repository helper with the reserved LAN address when the Docker subnet changes:

```bash
sudo bash scripts/server/configure-monitoring.sh --lan-ip LAN_IP
```

## Backup monitor is stale

```bash
sudo journalctl -u danzee-homelab-backup.service -n 100 --no-pager
sudo journalctl -t danzee-backup-heartbeat -n 30 --no-pager
sudo test -r /etc/danzee-homelab/uptime-kuma-backup-push-url
systemctl list-timers danzee-homelab-backup.timer --all
```

A first heartbeat attempt may fail immediately after the backup because Uptime Kuma has just restarted. The heartbeat script retries before recording a warning.


## Beszel is unavailable

```bash
sudo danzee-beszel-status
docker compose -f /opt/beszel/compose.yaml --profile agent ps
docker logs --tail 100 beszel
docker logs --tail 100 beszel-agent
curl -fsS http://127.0.0.1:8090/api/health
sudo ufw status numbered
```

Confirm that:

- the Hub and Agent are healthy;
- `/opt/beszel/socket` exists and is shared by both containers;
- the Docker socket proxy binds only to `127.0.0.1:2375`;
- TCP `8090` is allowed only from the trusted LAN and `tailscale0`;
- `/etc/danzee-beszel/agent.env` and `/etc/danzee-beszel/agent-key` remain root-only.
