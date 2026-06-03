# Monitoring with Prometheus

The NinerLog API exposes Prometheus metrics at `GET /metrics`. This guide shows
how to set up Prometheus scraping of those metrics while keeping the endpoint
unreachable from the public internet — and without forking or maintaining a
custom `docker-compose.yml`.

## The problem

`/metrics` is **unauthenticated** by design. Prometheus scrape targets are meant
to sit on a trusted network, not behind a login. That leaves two questions:

1. **Why can't a scraper reach `/metrics` today?**
2. **How do you reveal it to Prometheus — and only Prometheus — without exposing
   the rest of the API?**

### Why the scraper can't reach it (yet)

In the default stack, the metrics endpoint is sealed off:

- The `api` service only declares `expose: "3000"` — there is **no** `ports:`
  mapping — so port 3000 is reachable only on the internal `ninerlog-network`
  bridge. The host, your monitoring server, and the internet cannot connect to
  it.
- The frontend nginx reverse proxy only forwards `location /api/`. Because
  `/metrics` lives at the API root (not under `/api/`), it is **never** proxied
  to the public web.

So out of the box, a Prometheus scraper has no path to `/metrics` at all. That is
the secure default we want to preserve — we just need to open a single, narrow
door for the scraper.

## The approach: reveal it with a compose override

We expose the API on the host, then make it reachable **only** to the monitoring
host. The exposure is added via a **`docker-compose.override.yml`** file, which
Docker Compose merges automatically. This keeps the upstream `docker-compose.yml`
pristine — you never maintain a forked copy or remember extra `-f` flags.

The override binds the API port to the host so a scraper can reach it. *How* you
then restrict that to your monitoring host depends on your network — the key rule
is to **bind to a private address, never `0.0.0.0`**:

- **Private network interface** — bind the port to an interface only your
  monitoring host can see (e.g. a private LAN or VPN/overlay address), never the
  public NIC.
- **Host firewall** — bind to the host and allow port 3000 only from the
  monitoring host's IP.
- **Path-scoped host proxy** — bind to loopback and have a host-level reverse
  proxy expose just the `/metrics` path to the monitoring network.

```
┌───────────────────────────┐    private / monitoring network only
│  Prometheus (monitor host) │ ──────────────────────────────────────────┐
└───────────────────────────┘                                            │
                                                                         ▼
┌──────────────────────────── Docker host ────────────────────────────────┐
│                                                                          │
│   override.yml binds api → host (private iface / loopback)               │
│                         ┌──────────────────┐                             │
│                         │  api container   │  expose: 3000 (internal)    │
│                         └──────────────────┘                             │
│                                                                          │
│   public NIC: never binds port 3000  ✗ internet                         │
└──────────────────────────────────────────────────────────────────────────┘
```

## Setup

### 1. Add the override

Create `docker-compose.override.yml` next to `docker-compose.yml`. Bind the API
port to an address only your monitoring host can reach — **never `0.0.0.0`**.

Bind to a **private/monitoring interface** (replace with that interface's address
on the host):

```yaml
services:
  api:
    ports:
      # Private monitoring interface ONLY — never the public NIC.
      - "10.0.0.5:3000:3000"
```

Or bind to **loopback** if a host-level proxy will forward `/metrics` onward to
the monitoring network:

```yaml
services:
  api:
    ports:
      # Host loopback ONLY — a host-level proxy exposes /metrics onward.
      - "127.0.0.1:3000:3000"
```

Docker Compose loads `docker-compose.override.yml` automatically, so your normal
command keeps working unchanged:

```bash
docker compose up -d
```

Verify the binding is **not** public (the address column must show your private
IP or `127.0.0.1`, never `0.0.0.0`):

```bash
docker compose ps
# or
ss -tlnp | grep ':3000'
# 10.0.0.5:3000    ✓  (private interface only)
# 127.0.0.1:3000   ✓  (loopback only)
# 0.0.0.0:3000     ✗  (would be public — wrong!)
```

### 2. (Optional) Expose only `/metrics` via a host proxy

If you bound to loopback, run a small reverse proxy on the host that forwards
just the `/metrics` path to the monitoring network. This keeps the rest of the
API invisible even on the monitoring side. Any host-level proxy (nginx, Caddy,
etc.) works — point it at `http://127.0.0.1:3000/metrics` and deny everything
else.

### 3. Configure Prometheus on the monitoring host

Point Prometheus at whatever address you exposed in step 1 (or 2):

```yaml
scrape_configs:
  - job_name: 'ninerlog-api'
    scrape_interval: 15s
    metrics_path: /metrics
    static_configs:
      - targets: ['10.0.0.5:3000']   # the private address from the override
```

## Available metrics

See the API's
[metrics reference](https://github.com/fjaeckel/ninerlog-api/blob/main/docs/METRICS.md)
for the full list of exported series (HTTP, auth, database pool, notifications,
email delivery, rate limiting, and Go runtime metrics), plus ready-to-import
Grafana dashboards and Prometheus alerting rules.
