# Command cheat sheet

Replace placeholder values before running commands.

## Connect to the host

```bash
# LAN alias configured in ~/.ssh/config
ssh danzee-lab

# Tailscale IP
ssh your-linux-user@TAILSCALE_IP

# One-off remote command
ssh danzee-lab 'hostname && uptime'
```

## Host health

```bash
hostnamectl
uname -a
uptime
free -h
swapon --show
df -hT
lsblk -o NAME,TRAN,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL
sudo journalctl -p warning -b --no-pager
```

## Services

```bash
systemctl --failed
systemctl status docker --no-pager
systemctl status k3s --no-pager
systemctl status ollama --no-pager
systemctl status tailscaled --no-pager
```

## Docker

```bash
docker ps
docker ps -a
docker stats --no-stream
docker images
docker volume ls
docker network ls

docker compose -f /opt/homelab/compose.yaml ps
docker compose -f /opt/homelab/compose.yaml logs --tail 100
docker compose -f /opt/homelab/compose.yaml pull
docker compose -f /opt/homelab/compose.yaml up -d

docker logs --tail 100 mariadb
docker logs --tail 100 uptime-kuma
docker logs --tail 100 portainer
```

## k3s

```bash
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A -o wide
sudo k3s kubectl get all -A
sudo k3s kubectl get pv,pvc -A
sudo k3s kubectl get events -A --sort-by=.lastTimestamp
sudo k3s kubectl top nodes
sudo k3s kubectl top pods -A

sudo k3s kubectl apply -f k8s/guardrails.yaml
sudo k3s kubectl apply -f k8s/hello-lab.yaml
sudo k3s kubectl apply -f k8s/storage-demo.yaml

sudo k3s kubectl rollout restart deployment/hello-lab -n lab
sudo k3s kubectl logs -n lab deployment/hello-lab --tail=100
```

## Tailscale

```bash
tailscale status
tailscale ip -4
tailscale ping HOST_OR_TAILSCALE_IP
sudo tailscale up
sudo tailscale down
```

## UFW

```bash
sudo ufw status verbose
sudo ufw status numbered

# Trusted LAN SSH
sudo ufw allow from YOUR_LAN_CIDR to any port 22 proto tcp \
  comment 'SSH from trusted LAN'

# Tailscale SSH
sudo ufw allow in on tailscale0 to any port 22 proto tcp \
  comment 'SSH via Tailscale'

# App on LAN and Tailscale
sudo ufw allow from YOUR_LAN_CIDR to any port 8088 proto tcp \
  comment 'Private app from trusted LAN'

sudo ufw allow in on tailscale0 to any port 8088 proto tcp \
  comment 'Private app via Tailscale'
```

Always add and test restricted replacement rules before deleting a broad rule.

## Ollama

```bash
ollama list
ollama ps
ollama run qwen2.5:0.5b
curl http://127.0.0.1:11434/api/tags
sudo journalctl -u ollama -n 100 --no-pager
sudo systemctl restart ollama
```

### SSH tunnel to the local API

Run on the client:

```bash
ssh -N -L 11434:127.0.0.1:11434 danzee-lab
```

Then on the client:

```bash
curl http://127.0.0.1:11434/api/tags
```

## Backup operations

```bash
systemctl list-timers danzee-homelab-backup.timer --all
systemctl status danzee-homelab-backup.timer --no-pager

sudo systemctl start danzee-homelab-backup.service
sudo systemctl status danzee-homelab-backup.service --no-pager
sudo journalctl -u danzee-homelab-backup.service -n 100 --no-pager

sudo ls -lh /mnt/danzee-backup/danzee-homelab-backups
sudo bash scripts/server/validate-latest-backup.sh
```

A successful oneshot backup service normally becomes `inactive (dead)` after exiting with `status=0/SUCCESS`.

## USB mount

```bash
findmnt /mnt/danzee-backup
df -hT /mnt/danzee-backup
sudo findmnt --verify
```

Safe removal:

```bash
sync
sudo umount /mnt/danzee-backup
```

Do not remove the flash drive while a backup is running.

## Logs

```bash
sudo journalctl -u docker -n 100 --no-pager
sudo journalctl -u k3s -n 100 --no-pager
sudo journalctl -u ollama -n 100 --no-pager
sudo journalctl -u tailscaled -n 100 --no-pager
sudo journalctl -u danzee-homelab-backup.service -n 100 --no-pager
```

## Monitoring

```bash
# Uptime Kuma
docker ps --filter name=uptime-kuma
docker logs --tail 100 uptime-kuma

# Backup heartbeat
sudo journalctl -t danzee-backup-heartbeat -n 20 --no-pager
sudo /usr/local/sbin/danzee-backup-heartbeat

# Scoped firewall access
sudo ufw status numbered
```
