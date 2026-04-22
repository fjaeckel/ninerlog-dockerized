# Upgrading NinerLog

## Pulling Latest Images

```bash
# Pull newest images
docker compose pull

# Restart with new images (zero-downtime for stateless services)
docker compose up -d
```

## Pinning Versions

By default, the compose file uses `:latest` tags. To pin to a specific version:

```yaml
# docker-compose.override.yml
services:
  api:
    image: ghcr.io/fjaeckel/ninerlog-api:v1.2.0
  frontend:
    image: ghcr.io/fjaeckel/ninerlog-frontend:v1.2.0
```

Then:

```bash
docker compose up -d
```

## Database Migrations

The API container runs database migrations automatically on startup. No manual migration step is needed.

If a migration fails, the API will not start. Check the logs:

```bash
docker compose logs api
```

## Rollback

To roll back to a previous version:

```bash
# Stop
docker compose down

# Pin the older version in docker-compose.override.yml, then:
docker compose up -d
```

> **Note**: Database migrations are forward-only. Rolling back the application version may require manual database changes if the newer version added schema changes.

## Backup Before Upgrading

```bash
# Dump the database
docker compose exec postgres pg_dump -U ninerlog ninerlog > backup-$(date +%F).sql
```

Restore if needed:

```bash
cat backup-2026-04-22.sql | docker compose exec -T postgres psql -U ninerlog ninerlog
```
