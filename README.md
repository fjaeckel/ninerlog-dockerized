# NinerLog — Self-Hosted Deployment

Run your own instance of [NinerLog](https://ninerlog.app), the EASA/FAA compliant pilot logbook.

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/fjaeckel/ninerlog-dockerized.git
cd ninerlog-dockerized

# 2. Configure environment
cp .env.example .env
# Edit .env — at minimum set JWT_SECRET, REFRESH_SECRET, POSTGRES_PASSWORD

# 3. Log in to GitHub Container Registry (images are private for now)
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin

# 4. Start everything
docker compose up -d

# 5. Open NinerLog
open http://localhost
```

The stack pulls pre-built images from GitHub Container Registry — no build step needed.

## What's Included

| Service | Image | Port |
|---------|-------|------|
| **API** | `ghcr.io/fjaeckel/ninerlog-api:latest` | 3000 (internal) |
| **Frontend** | `ghcr.io/fjaeckel/ninerlog-frontend:latest` | 80 / 443 |
| **PostgreSQL** | Custom (Alpine + auto-TLS) | 5432 (internal) |
| **Certbot** | `certbot/certbot:latest` | — |
| **DB Backup** | Custom (Alpine + pg_dump) | — |

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│   Browser   │────▶│  Frontend   │────▶│   API        │
│             │     │  (nginx)    │     │  (Go)        │
└─────────────┘     │  :80/:443   │     │  :3000       │
                    └─────────────┘     └──────┬───────┘
                                               │
                                        ┌──────▼───────┐
                                        │  PostgreSQL  │
                                        │  :5432 (TLS) │
                                        └──────────────┘
```

- **Frontend** serves the React PWA and reverse-proxies `/api/*` to the API container.
- **PostgreSQL** uses auto-generated self-signed TLS certificates for wire encryption between containers.
- **Certbot** handles Let's Encrypt certificate renewal for HTTPS.
- **DB Backup** runs scheduled `pg_dump` snapshots, gzip-compressed, with automatic retention pruning.

## Configuration

All configuration is done via environment variables in `.env`. See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for the full reference.

### Minimum Required

| Variable | Description |
|----------|-------------|
| `POSTGRES_PASSWORD` | Database password |
| `JWT_SECRET` | Secret key for access tokens (min. 32 chars) |
| `REFRESH_SECRET` | Secret key for refresh tokens (min. 32 chars) |

### For Production (HTTPS)

| Variable | Description |
|----------|-------------|
| `TLS_DOMAIN` | Your domain name (e.g. `logbook.example.com`) |
| `CORS_ORIGIN` | Must match your domain (e.g. `https://logbook.example.com`) |
| `VITE_API_BASE_URL` | Usually `/api/v1` (default) |

See [docs/HTTPS.md](docs/HTTPS.md) for the full TLS/Let's Encrypt setup.

## Updating

```bash
# Pull latest images
docker compose pull

# Restart with new images
docker compose up -d
```

See [docs/UPGRADING.md](docs/UPGRADING.md) for version pinning and migration notes.

## Documentation

- [Configuration Reference](docs/CONFIGURATION.md) — All environment variables
- [HTTPS Setup](docs/HTTPS.md) — Let's Encrypt / TLS configuration
- [Upgrading](docs/UPGRADING.md) — Pulling new versions, migrations
- [Backups](docs/BACKUPS.md) — Automated database backups and restore
- [API Documentation](https://github.com/fjaeckel/ninerlog-api/blob/main/api-spec/openapi.yaml) — OpenAPI 3.1 specification

## License

See the individual repositories for license information:
- [ninerlog-api](https://github.com/fjaeckel/ninerlog-api)
- [ninerlog-frontend](https://github.com/fjaeckel/ninerlog-frontend)
