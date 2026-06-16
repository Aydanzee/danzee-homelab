# Monitoring

Uptime Kuma provides the lightweight operations dashboard for the reference homelab. It monitors both customer-facing services and internal lab infrastructure without exposing the Docker socket.

## Monitor layout

The status page is separated into two groups:

### Products

- Axiom Labs
- TaxCalc
- DyadKeep

### Homelab infrastructure

- Axiom Local
- k3s Hello App
- Nightly Encrypted Backup
- Portainer

Keeping these groups separate prevents a temporary lab issue from making public products appear unavailable.

## Recommended monitor configuration

| Monitor | Type | Target | Purpose |
|---|---|---|---|
| Axiom Local | HTTP keyword | `http://LAN_IP:8088/api/health` | Confirms the web interface and Ollama connection are healthy |
| k3s Hello App | HTTP | `http://LAN_IP:30080` | Confirms the Kubernetes test workload is reachable |
| Portainer | HTTPS | `https://LAN_IP:9443` | Confirms the container-management interface is reachable |
| Nightly Encrypted Backup | Push | Generated Uptime Kuma Push URL | Confirms a backup completed and the success hook ran |

For the Axiom Local monitor, use the keyword:

```text
"online":true
```

Portainer uses a local certificate, so its monitor must allow the expected self-signed TLS certificate.

## Docker-to-host firewall path

Uptime Kuma runs inside Docker. UFW therefore needs narrowly scoped rules that permit only the Uptime Kuma Docker subnet to reach:

- TCP `8088` for Axiom Local;
- TCP `9443` for Portainer.

The supplied configuration script discovers the active Docker network and subnet instead of hardcoding them:

```bash
sudo bash scripts/server/configure-monitoring.sh --lan-ip LAN_IP
```

Do not allow every Docker subnet or expose these ports publicly just to make monitoring work.

## Backup heartbeat

The backup service runs this hook only after a successful backup:

```text
ExecStartPost=/usr/local/sbin/danzee-backup-heartbeat
```

The heartbeat script:

1. reads the Push URL from a root-only file;
2. sends an `up` status after backup success;
3. retries while Uptime Kuma finishes restarting after its own volume snapshot;
4. logs delivery through the system journal;
5. does not convert a valid backup into a failed backup if monitoring delivery is unavailable.

The Push URL is stored at:

```text
/etc/danzee-homelab/uptime-kuma-backup-push-url
```

It must never be committed. Treat it like a credential because anyone holding the token could submit a false heartbeat.

## Useful checks

```bash
# Uptime Kuma container
docker ps --filter name=uptime-kuma
docker logs --tail 100 uptime-kuma

# Firewall rules
sudo ufw status numbered

# Backup heartbeat logs
sudo journalctl -t danzee-backup-heartbeat -n 20 --no-pager

# Backup service and timer
sudo systemctl status danzee-homelab-backup.service --no-pager
systemctl list-timers danzee-homelab-backup.timer --all
```
