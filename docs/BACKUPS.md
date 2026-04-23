# Database Backups

NinerLog includes an automated backup service that continuously dumps the PostgreSQL database into compressed files.

## How It Works

The `db-backup` container runs alongside the other services and:

1. Waits for PostgreSQL to be healthy
2. Runs `pg_dump` on a configurable schedule (default: every 6 hours)
3. Compresses the dump with gzip (level 9)
4. Writes the file to the backup directory as `ninerlog_YYYYMMDD_HHMMSSz.sql.gz`
5. Prunes old backups beyond the retention count

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_PATH` | `./backups` | Host directory where backups are written |
| `BACKUP_INTERVAL` | `21600` | Seconds between backups (21600 = 6 hours) |
| `BACKUP_RETENTION` | `30` | Number of backup files to keep |

Add these to your `.env` file to customize:

```bash
# Backup every 12 hours, keep 14 backups (7 days)
BACKUP_INTERVAL=43200
BACKUP_RETENTION=14
BACKUP_PATH=/mnt/backups/ninerlog
```

## Checking Backup Status

```bash
# View backup logs
docker logs ninerlog-db-backup

# List existing backups
ls -lh backups/
```

## Restoring from Backup

```bash
# 1. Stop the API so no writes occur during restore
docker compose stop api

# 2. Decompress and restore
gunzip -c backups/ninerlog_20260423_060000Z.sql.gz | \
  docker compose exec -T postgres psql -U ninerlog -d ninerlog

# 3. Restart the API
docker compose start api
```

## Shipping Backups Off-Site

The backup directory is a standard host-mounted path. Use any file-sync tool to ship backups to a remote location:

```bash
# rsync to a remote server
rsync -az ./backups/ user@backup-host:/backups/ninerlog/

# rclone to S3-compatible storage
rclone sync ./backups/ remote:ninerlog-backups/
```

Consider setting up a cron job on the host to run the sync periodically.

## Manual Backup

To trigger a one-off backup outside the schedule:

```bash
docker compose exec db-backup /usr/local/bin/db-backup.sh &
# Or run pg_dump directly:
docker compose exec postgres pg_dump -U ninerlog ninerlog | gzip -9 > manual_backup.sql.gz
```
