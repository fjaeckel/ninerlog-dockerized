#!/bin/sh
set -e

# Generate self-signed TLS certificate for PostgreSQL if none exists.
# These certs encrypt the wire between the API container and the database
# container on the Docker bridge network. They are NOT used for external
# traffic (nginx handles that via Let's Encrypt).
#
# This script runs as an entrypoint wrapper — it generates certs, then
# exec's the original docker-entrypoint.sh with all arguments.

CERT_DIR="/var/lib/postgresql/ssl"
CERT="$CERT_DIR/server.crt"
KEY="$CERT_DIR/server.key"

if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
  echo "Generating self-signed TLS certificate for PostgreSQL..."
  mkdir -p "$CERT_DIR"
  openssl req -new -x509 -days 3650 -nodes \
    -out "$CERT" \
    -keyout "$KEY" \
    -subj "/CN=ninerlog-db" 2>/dev/null
  # PostgreSQL requires strict permissions on the key file
  chmod 600 "$KEY"
  chown 70:70 "$CERT" "$KEY"   # UID/GID 70 = postgres in alpine
  echo "PostgreSQL TLS certificate generated."
else
  # Ensure permissions are correct on existing certs
  chmod 600 "$KEY"
  chown 70:70 "$CERT" "$KEY" 2>/dev/null || true
  echo "PostgreSQL TLS certificate already exists."
fi

# Hand off to the real postgres entrypoint
exec docker-entrypoint.sh "$@"
