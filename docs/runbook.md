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
