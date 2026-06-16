# Architecture

## Host profile

The reference build targets a modest x86_64 laptop with approximately:

- dual-core Intel CPU;
- 4 GB RAM;
- swap enabled;
- one internal disk;
- one existing USB flash drive used as an encrypted backup destination;
- reserved LAN address;
- no router port forwarding.

The design favours low idle memory, simple recovery, and services that restart automatically after power loss.

## Network paths

### Home access

```text
Mac or trusted LAN device
        |
        | trusted LAN
        v
Ubuntu host
```

### Remote access

```text
Mac or phone
     |
     | authenticated Tailscale network
     v
tailscale0 on Ubuntu host
```

### AI request path

```text
Browser
  |
  v
Axiom Local :8088
  |
  v
Ollama 127.0.0.1:11434
```

Ollama remains loopback-only. The browser never talks to the Ollama API directly.

## Workload separation

Docker and k3s run independently:

- Docker uses the Docker Engine.
- k3s uses containerd internally.
- Docker Compose manages long-running utility services.
- k3s provides a Kubernetes learning environment.

## Backup flow

```text
Live services
  |
  +-- MariaDB logical dump
  +-- Docker application volumes
  +-- k3s SQLite online backup
  +-- k3s local storage
  +-- project and system configuration
  |
  v
temporary staging directory
  |
  +-- internal SHA-256 checksums
  +-- compressed tar archive
  +-- AES-256-CBC encryption with PBKDF2
  |
  v
existing USB filesystem mounted by UUID
```

The USB filesystem is not formatted by the installation script.

## Monitoring flow

```text
Uptime Kuma container
  |
  +-- HTTP keyword --> Axiom Local health endpoint
  +-- HTTP ---------> k3s Hello App
  +-- HTTPS --------> Portainer

Successful systemd backup
  |
  +-- ExecStartPost --> backup heartbeat
                        |
                        v
                  Uptime Kuma Push monitor
```

UFW permits only the discovered Uptime Kuma Docker subnet to reach the host ports used by Axiom Local and Portainer. The backup heartbeat retries because Uptime Kuma is briefly restarted while its persistent volume is archived.
