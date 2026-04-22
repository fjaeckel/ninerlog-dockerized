# Configuration Reference

All NinerLog configuration is done via environment variables in the `.env` file.

## Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `POSTGRES_PASSWORD` | PostgreSQL password | `my-secure-db-password` |
| `JWT_SECRET` | HMAC secret for access tokens (min 32 chars) | `openssl rand -hex 32` |
| `REFRESH_SECRET` | HMAC secret for refresh tokens (min 32 chars) | `openssl rand -hex 32` |

### Generating Secrets

```bash
# Generate random secrets
echo "JWT_SECRET=$(openssl rand -hex 32)" >> .env
echo "REFRESH_SECRET=$(openssl rand -hex 32)" >> .env
echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)" >> .env
```

## Database

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_DB` | `ninerlog` | Database name |
| `POSTGRES_USER` | `ninerlog` | Database user |
| `POSTGRES_PASSWORD` | — | Database password |

Data is persisted in a Docker volume (`postgres_data`). The database uses auto-generated self-signed TLS certificates for wire encryption between the API and Postgres containers.

## Authentication

| Variable | Default | Description |
|----------|---------|-------------|
| `JWT_SECRET` | — | HMAC signing key for access tokens |
| `REFRESH_SECRET` | — | HMAC signing key for refresh tokens |
| `JWT_EXPIRES_IN` | `15m` | Access token lifetime (Go duration) |
| `REFRESH_EXPIRES_IN` | `7d` | Refresh token lifetime (Go duration) |

## Networking

| Variable | Default | Description |
|----------|---------|-------------|
| `CORS_ORIGIN` | `http://localhost` | Allowed CORS origin (must match your domain) |
| `TLS_DOMAIN` | — | Domain for HTTPS / Let's Encrypt |
| `FRONTEND_PORT` | `80` | HTTP port on the host |
| `FRONTEND_TLS_PORT` | `443` | HTTPS port on the host |

## Server

| Variable | Default | Description |
|----------|---------|-------------|
| `GIN_MODE` | `release` | Gin framework mode: `debug`, `release`, `test` |
| `LOG_LEVEL` | `info` | Log verbosity: `debug`, `info`, `warn`, `error` |

## App

| Variable | Default | Description |
|----------|---------|-------------|
| `VITE_API_BASE_URL` | `/api/v1` | API base URL as seen by the browser |
| `VITE_ENV` | `production` | Environment label |
| `APP_NAME` | — | Custom application name |
| `BETA_PASSWORD` | — | If set, registration requires this password |

## Admin

| Variable | Default | Description |
|----------|---------|-------------|
| `ADMIN_EMAIL` | — | Email address for the admin account |

## Email / SMTP

| Variable | Default | Description |
|----------|---------|-------------|
| `SMTP_HOST` | — | SMTP server hostname (empty = log to stdout) |
| `SMTP_PORT` | `587` | SMTP port |
| `SMTP_USERNAME` | — | SMTP auth username |
| `SMTP_PASSWORD` | — | SMTP auth password |
| `SMTP_FROM` | `noreply@ninerlog.app` | Sender address |

## Notifications

| Variable | Default | Description |
|----------|---------|-------------|
| `NOTIFICATION_CHECK_INTERVAL` | `1h` | How often to check for notifications (Go duration) |
