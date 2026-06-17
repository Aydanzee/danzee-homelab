# Resource monitoring with Beszel

Beszel provides lightweight historical resource monitoring for the Ubuntu host and its Docker workloads.

## Responsibilities

| Tool | Responsibility |
|---|---|
| Uptime Kuma | Service availability, status checks, and backup heartbeat |
| Portainer | Container management, logs, console access, and live inspection |
| Beszel | Historical CPU, memory, swap, disk, network, temperature, and container usage |
| k3s Metrics API | Current Kubernetes node and pod resource usage |

## Reference deployment

The reference build uses:

- a pinned Beszel Hub and Agent;
- host networking for the Hub and Agent;
- a shared Unix socket between the Hub and Agent;
- a loopback-only Docker socket proxy;
- root-only agent credentials;
- UFW access limited to the trusted LAN and `tailscale0`;
- CPU and memory limits suitable for a 4 GB host.

The Docker socket proxy exposes only the read-only endpoints needed for container metrics. It is bound to `127.0.0.1`, so it is not reachable from the LAN.

## Install

```bash
sudo bash scripts/server/install-beszel-monitoring.sh \
  --lan-ip LAN_IP \
  --lan-cidr LAN_CIDR
```

Then:

1. open `http://LAN_IP:8090`;
2. create the initial administrator account;
3. choose **Add System -> Docker**;
4. set **Host / IP** to `/beszel_socket/beszel.sock`;
5. copy the generated public key and token;
6. run `sudo danzee-beszel-agent-setup`;
7. enter the public key and token only into the root-only prompts.

Never commit the token, key file, PocketBase data, or uploaded application data.

## Health check

```bash
sudo danzee-beszel-status
```

Expected components:

```text
beszel
beszel-agent
beszel-socket-proxy
```

The Hub and Agent should report healthy. The socket proxy should bind only to `127.0.0.1:2375`.

## Useful alerts

Reasonable starting thresholds for a small laptop host:

- CPU above 90% for 10 minutes;
- memory above 85%;
- disk above 80%;
- temperature above 85°C;
- system offline for 2 minutes.

Tune the values after enough history exists to understand the host's normal behaviour.

## Network-accounting limitation

Beszel measures the host and its containers. It does not automatically measure total household traffic when the Ubuntu host is not the network gateway.

Whole-network accounting requires one of:

- counters or an API exposed by the router;
- SNMP support;
- a router or gateway controlled by the operator;
- traffic routed through a monitored interface.

## Backup status

The reference encrypted backup currently covers the core homelab configuration, MariaDB, Portainer, Uptime Kuma, k3s state, and local storage.

Beszel data should be added only through a tested, consistent PocketBase snapshot or a brief controlled service stop. Do not copy a live database blindly and claim it is restorable.
