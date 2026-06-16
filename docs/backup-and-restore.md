# Backup and restore

## What is protected

The supplied backup job collects:

- Compose configuration;
- optional private-app files if the configured directory exists;
- user-maintained k3s manifests;
- MariaDB logical dump;
- Portainer and Uptime Kuma volume archives;
- k3s SQLite online backup;
- k3s server configuration excluding the live database and socket;
- k3s local-path persistent storage;
- selected systemd, UFW, mount, and Ollama information;
- internal SHA-256 checksums.

Ollama model blobs are intentionally excluded because they can be downloaded again and would unnecessarily multiply backup size.

## Encryption

The backup archive is encrypted before being copied to USB:

```text
AES-256-CBC
PBKDF2
200,000 iterations
random salt
```

The root-only passphrase is stored at:

```text
/root/.config/danzee-backup/backup.passphrase
```

Keep a recovery copy on a separate trusted device. Never commit it.

## Manual backup

```bash
sudo systemctl start danzee-homelab-backup.service
sudo journalctl -u danzee-homelab-backup.service -n 100 --no-pager
```

## Validate the latest archive

```bash
sudo bash scripts/server/validate-latest-backup.sh
```

This is non-destructive. It extracts into a temporary directory and deletes the temporary files afterward.

## Manual decryption

```bash
sudo openssl enc \
  -d \
  -aes-256-cbc \
  -pbkdf2 \
  -iter 200000 \
  -pass file:/root/.config/danzee-backup/backup.passphrase \
  -in /path/to/backup.tar.gz.enc \
  -out /var/tmp/backup.tar.gz
```

Then:

```bash
sudo mkdir -p /var/tmp/danzee-restore
sudo tar -xzf /var/tmp/backup.tar.gz -C /var/tmp/danzee-restore
```

Do not copy restored data over live services without a service-specific recovery plan.

## MariaDB restore outline

1. Inspect the SQL dump.
2. Stop applications that write to the database.
3. Take an additional current backup.
4. Restore into a temporary database or disposable container first.
5. Validate schema and records.
6. Only then restore to the live database.

Example disposable validation:

```bash
gunzip -c docker/mariadb-all-databases.sql.gz | head
```

## k3s restore warning

Restoring the k3s datastore is destructive and version-sensitive. Stop k3s, preserve the current datastore, and verify the k3s version before replacing state.

The routine validation script only runs `PRAGMA integrity_check`; it does not alter the live cluster.
