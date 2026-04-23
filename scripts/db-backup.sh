#!/bin/sh
set -eu

# Configuration (via environment variables)
BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-21600}"   # seconds between backups (default: 6h)
BACKUP_RETENTION="${BACKUP_RETENTION:-30}"     # number of backups to keep
PGHOST="${PGHOST:-postgres}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-ninerlog}"
PGDATABASE="${PGDATABASE:-ninerlog}"

mkdir -p "${BACKUP_DIR}"

log() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"
}

do_backup() {
  timestamp="$(date -u '+%Y%m%d_%H%M%SZ')"
  filename="ninerlog_${timestamp}.sql.gz"
  filepath="${BACKUP_DIR}/${filename}"

  log "Starting backup → ${filename}"

  if pg_dump -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" \
       --no-password --clean --if-exists --format=plain | gzip -9 > "${filepath}"; then
    size="$(du -h "${filepath}" | cut -f1)"
    log "Backup complete: ${filename} (${size})"
  else
    log "ERROR: Backup failed"
    rm -f "${filepath}"
    return 1
  fi
}

prune_old() {
  count="$(find "${BACKUP_DIR}" -name 'ninerlog_*.sql.gz' -type f | wc -l)"
  if [ "${count}" -gt "${BACKUP_RETENTION}" ]; then
    excess=$((count - BACKUP_RETENTION))
    log "Pruning ${excess} old backup(s) (keeping ${BACKUP_RETENTION})"
    # shellcheck disable=SC2012
    ls -1t "${BACKUP_DIR}"/ninerlog_*.sql.gz | tail -n "${excess}" | xargs rm -f
  fi
}

# --- Main loop ---
log "Backup scheduler started (interval=${BACKUP_INTERVAL}s, retention=${BACKUP_RETENTION})"

while true; do
  do_backup || true
  prune_old  || true
  log "Next backup in ${BACKUP_INTERVAL}s"
  sleep "${BACKUP_INTERVAL}"
done
