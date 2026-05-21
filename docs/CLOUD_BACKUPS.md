# Cloud Backups

NinerLog can periodically export each user's logbook as a compressed JSON
file and upload it to a **cloud storage destination** of their choice.
Storage backends are pluggable — the API ships with a registry of
providers and the UI renders a configuration form for whichever ones are
registered. Backups are configured **per user** from the in-app
*Settings → Cloud backups* page; operators only need to enable the
feature on the server.

This is independent from the [`db-backup`](BACKUPS.md) container, which
takes server-side `pg_dump` snapshots of the entire database. Cloud
backups give end users a self-service, encrypted-at-rest export they own
and can restore from on a different instance.

## Available providers

| Provider | Status   | Notes                                                                                         |
| -------- | -------- | --------------------------------------------------------------------------------------------- |
| `s3`     | shipping | Amazon S3 and any S3-compatible object store (MinIO, Backblaze B2, Cloudflare R2, Wasabi, …). |

Additional providers (e.g. WebDAV, Google Cloud Storage, Azure Blob,
SFTP) are planned and will appear here as they ship. Once a provider is
compiled into the API image it shows up automatically in the user-facing
*"Add destination"* dialog — there is no per-provider operator
configuration.

## Architecture at a glance

```
┌──────────┐   schedule   ┌────────────┐   provider plugin   ┌────────────────┐
│ user UI  │ ───────────► │ ninerlog-  │ ──────────────────► │ user's cloud   │
│ Settings │              │   api      │  (S3, …)            │ storage        │
└──────────┘              └─────┬──────┘                     └────────────────┘
                                │
                          encrypted creds
                                ▼
                          ┌──────────┐
                          │ postgres │
                          └──────────┘
```

- **Credentials** are encrypted with AES-256-GCM using
  `BACKUP_CREDENTIALS_KEY` before being stored in the database. The
  plaintext never touches disk. Every provider plugin uses the same
  encryption envelope, regardless of how many secret fields it needs.
- **Configuration** (non-secret fields like bucket / endpoint / host) is
  stored in plaintext.
- **Backup payloads** are gzipped JSON
  (`ninerlog-backup-<timestamp>.json.gz`) and uploaded directly from the
  API to the user's storage. NinerLog never proxies the bytes through
  any other service.
- **Provider schemas** (which fields a destination needs, which are
  secret, validation rules) are advertised by each plugin via
  `GET /api/v1/backups/providers` so the frontend can render a generic
  form.

## Enabling the feature

Cloud backups are **off by default**. To turn them on, set a 32-byte
master key in your `.env` and restart the stack:

```bash
# Generate a fresh key (32 random bytes, base64-encoded)
openssl rand -base64 32

# Then in .env:
BACKUP_CREDENTIALS_KEY=<paste-the-output-here>
```

```bash
docker compose up -d api
docker logs ninerlog-api | grep -i backup
# ✅ Cloud backups enabled
# ✅ Cloud backup scheduler started
```

If `BACKUP_CREDENTIALS_KEY` is empty or unset you'll see:

```
ℹ️  Cloud backups disabled (set BACKUP_CREDENTIALS_KEY to enable)
```

and `GET /api/v1/backups/destinations` will return **503**.

> **⚠️ Treat `BACKUP_CREDENTIALS_KEY` like a database password.** It
> decrypts every user's stored credentials across every provider. Store
> it in your secret manager, not in version control. Losing it means
> existing destinations can no longer run; rotating it requires
> re-entering credentials for every destination.

## What gets backed up

Each run exports the calling user's data only:

- Flights and flight legs
- Aircraft, airports, pilots, and other reference data the user owns
- User profile (no password hashes, no session tokens)

The result is a single gzipped JSON document with a stable, provider-
independent schema. The same file produced by any backend can be
imported into any NinerLog instance.

## Per-user configuration

End users configure their own destinations in the web app. From the
operator's side there is nothing provider-specific to do beyond
enabling the feature.

Every destination — regardless of provider — has these common fields:

| Field               | Required | Notes                                                            |
| ------------------- | -------- | ---------------------------------------------------------------- |
| `provider`          | yes      | One of the providers listed above (e.g. `s3`).                   |
| `name`              | yes      | User-facing label.                                               |
| `schedule`          | yes      | `manual`, `daily`, `weekly`, or `monthly`.                       |
| `schedule_hour_utc` | yes      | Hour-of-day in UTC at which scheduled runs fire (0–23).          |

The remaining fields are provider-specific and described by each
plugin's schema. When the user saves a destination the API runs the
provider's `Validate` step against their credentials and rejects the
destination if the target is unreachable or permissions are
insufficient.

### Provider-specific fields

#### `s3` — Amazon S3 and compatible

Configuration (non-secret):

| Field      | Required | Notes                                                                                                  |
| ---------- | -------- | ------------------------------------------------------------------------------------------------------ |
| `bucket`   | yes      | Existing bucket name. NinerLog never creates buckets.                                                  |
| `region`   | yes      | e.g. `us-east-1`. Use `us-east-1` for stores that don't enforce regions.                               |
| `prefix`   | no       | Key prefix; defaults to `ninerlog-backups/`. A trailing `/` is added automatically.                    |
| `endpoint` | no       | Leave empty for AWS S3. Set to e.g. `https://s3.eu-central-003.backblazeb2.com` for compatible stores. |

Credentials (encrypted at rest): `access_key_id`, `secret_access_key`.

Minimum AWS IAM policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::my-ninerlog-backups",
      "Condition": {
        "StringLike": { "s3:prefix": ["ninerlog-backups/*"] }
      }
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:AbortMultipartUpload"],
      "Resource": "arn:aws:s3:::my-ninerlog-backups/ninerlog-backups/*"
    }
  ]
}
```

`s3:GetObject` / `s3:DeleteObject` are **not** required by NinerLog —
restoring is done by the user downloading the object directly from
their storage console or CLI.

## Scheduling

A single in-process scheduler in the API container ticks once per
minute, picks up destinations whose `next_run_at` is due, and dispatches
them with a small jitter to avoid stampeding. Per-user serialization
ensures one user can't have two overlapping uploads, and the same loop
serves every provider.

> If you ever scale `api` to more than one replica, only one of them
> should run the scheduler. The current image always runs it; stick to a
> single API replica until horizontal scaling is added.

Manual runs (the *"Run now"* button in the UI) bypass the scheduler and
dispatch immediately.

## Restoring a backup

The exported file is plain gzipped JSON — there is no special restore
flow on the server, and it does not matter which provider produced the
file. Users restore by:

1. Downloading the object from their storage backend.
2. Importing it from the *Settings → Import* page on any NinerLog
   instance.

Operators do not need to touch the database for a user-initiated
restore.

## Operations

### Verifying the feature is enabled

```bash
docker compose exec api wget -qO- http://localhost:3000/api/v1/backups/providers
# → JSON listing the registered providers and their field schemas.
```

### Common log messages

| Message                                                | Meaning                                                                         |
| ------------------------------------------------------ | ------------------------------------------------------------------------------- |
| `✅ Cloud backups enabled`                             | Feature active, key valid.                                                      |
| `✅ Cloud backup scheduler started`                    | Periodic loop running.                                                          |
| `ℹ️  Cloud backups disabled (...)`                     | `BACKUP_CREDENTIALS_KEY` not set.                                               |
| `Invalid BACKUP_CREDENTIALS_KEY: ...` (fatal)          | Key is not 32 bytes / not valid base64.                                         |
| `cloudbackup scheduler: run failed (dest=...)`         | A user's run failed; check the destination's run history in the UI for details. |

### Rotating `BACKUP_CREDENTIALS_KEY`

Key rotation is **not** automated. To rotate:

1. Have each user remove and re-create their destinations *before*
   rotating the key, **or** accept that all existing destinations will
   stop working until users re-enter their credentials.
2. Replace the value in `.env` and restart `api`.

Rotation tooling is tracked as a future enhancement.

### Disabling the feature

Remove (or empty) `BACKUP_CREDENTIALS_KEY` and restart `api`. Existing
destinations remain in the database but the API will return `503` for
all `/api/v1/backups/*` endpoints. Nothing is deleted.

## Troubleshooting

**`503 Service Unavailable` from `/api/v1/backups/*`**
→ `BACKUP_CREDENTIALS_KEY` is empty in the API container. Confirm with
`docker compose exec api env | grep BACKUP_CREDENTIALS_KEY`. If `.env`
has the value but the container does not, ensure `docker-compose.yml`
passes it through (the bundled compose file already does).

**Destination validation fails with "not found" / "no such bucket"**
→ The target (bucket, container, host…) doesn't exist or the
credentials are for a different account. NinerLog never creates the
remote target itself.

**Validation succeeds but scheduled runs never fire**
→ Check `schedule` is not `manual`, and that the API container's clock
is correct (`docker compose exec api date -u`). The scheduler uses UTC.

**`Invalid BACKUP_CREDENTIALS_KEY` on startup**
→ The value must decode to exactly 32 bytes. Re-generate with
`openssl rand -base64 32` and try again.

**A provider isn't listed in the UI**
→ Only providers compiled into the running API image appear. Check
`GET /api/v1/backups/providers` to see what the server has registered,
and pull a newer `ghcr.io/fjaeckel/ninerlog-api` image if a provider
you expect is missing.
