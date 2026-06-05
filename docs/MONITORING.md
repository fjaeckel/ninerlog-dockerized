# Monitoring with Prometheus

The NinerLog stack exposes Prometheus metrics for three components:

| Component  | Source                                            | Internal port |
| ---------- | ------------------------------------------------- | ------------- |
| API        | Go app — `GET /metrics`                            | `3000`        |
| nginx      | `nginx-exporter` sidecar (scrapes `stub_status`)  | `9113`        |
| PostgreSQL | `postgres-exporter` sidecar                       | `9187`        |

This guide shows how to set up Prometheus scraping of those metrics while keeping
the endpoints unreachable from the public internet — and without forking or
maintaining a custom `docker-compose.yml`.

The two exporters (`nginx-exporter` and `postgres-exporter`) are part of the
default stack in `docker-compose.yml`, but — exactly like the API — their ports
are **internal only**. They publish nothing to the host until you opt in via a
compose override.

## The problem

`/metrics` is **unauthenticated** by design. Prometheus scrape targets are meant
to sit on a trusted network, not behind a login. That leaves two questions:

1. **Why can't a scraper reach `/metrics` today?**
2. **How do you reveal it to Prometheus — and only Prometheus — without exposing
   the rest of the API?**

### Why the scraper can't reach it (yet)

In the default stack, the metrics endpoints are sealed off:

- The `api`, `nginx-exporter`, and `postgres-exporter` services only declare
  `expose` — there is **no** `ports:` mapping — so their ports (3000, 9113, 9187)
  are reachable only on the internal `ninerlog-network` bridge. The host, your
  monitoring server, and the internet cannot connect to them.
- The frontend nginx reverse proxy only forwards `location /api/`. The API
  `/metrics` path, the nginx `stub_status` port (8080), and the exporter ports are
  **never** proxied to the public web.

So out of the box, a Prometheus scraper has no path to any of the metrics at all.
That is the secure default we want to preserve — we just need to open a few
narrow doors for the scraper.

## The approach: reveal it with a compose override

We expose the API on the host, then make it reachable **only** to the monitoring
host. The exposure is added via a **`docker-compose.override.yml`** file, which
Docker Compose merges automatically. This keeps the upstream `docker-compose.yml`
pristine — you never maintain a forked copy or remember extra `-f` flags.

The override binds the metrics ports to the host so a scraper can reach them.
*How* you then restrict that to your monitoring host depends on your network — the
key rule is to **bind to a private address, never `0.0.0.0`**:

- **Private network interface** — bind the ports to an interface only your
  monitoring host can see (e.g. a private LAN or VPN/overlay address), never the
  public NIC.
- **Host firewall** — bind to the host and allow ports 3000 / 9113 / 9187 only
  from the monitoring host's IP.
- **Path-scoped host proxy** — bind to loopback and have a host-level reverse
  proxy forward only the metrics paths to the monitoring network.

```
┌───────────────────────────┐    private / monitoring network only
│  Prometheus (monitor host) │ ──────────────────────────────────────────┐
└───────────────────────────┘                                            │
                                                                         ▼
┌──────────────────────────── Docker host ────────────────────────────────┐
│                                                                          │
│   override.yml binds metrics ports → host (private iface / loopback)     │
│        ┌─────────────┐  ┌────────────────┐  ┌───────────────────┐        │
│        │ api  :3000  │  │ nginx-exporter │  │ postgres-exporter │        │
│        │             │  │     :9113      │  │      :9187        │        │
│        └─────────────┘  └────────────────┘  └───────────────────┘        │
│              all expose-only on the internal ninerlog-network            │
│                                                                          │
│   public NIC: never binds 3000 / 9113 / 9187  ✗ internet                │
└──────────────────────────────────────────────────────────────────────────┘
```

## Setup

### 1. Add the override

Create `docker-compose.override.yml` next to `docker-compose.yml`. Bind each
metrics port to an address only your monitoring host can reach — **never
`0.0.0.0`**.

Bind to a **private/monitoring interface** (replace with that interface's address
on the host):

```yaml
services:
  api:
    ports:
      # Private monitoring interface ONLY — never the public NIC.
      - "10.0.0.5:3000:3000"
  nginx-exporter:
    ports:
      - "10.0.0.5:9113:9113"
  postgres-exporter:
    ports:
      - "10.0.0.5:9187:9187"
```

Or bind to **loopback** if a host-level proxy will forward the metrics paths
onward to the monitoring network:

```yaml
services:
  api:
    ports:
      # Host loopback ONLY — a host-level proxy exposes /metrics onward.
      - "127.0.0.1:3000:3000"
  nginx-exporter:
    ports:
      - "127.0.0.1:9113:9113"
  postgres-exporter:
    ports:
      - "127.0.0.1:9187:9187"
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
ss -tlnp | grep -E ':(3000|9113|9187)'
# 10.0.0.5:9113    ✓  (private interface only)
# 127.0.0.1:9187   ✓  (loopback only)
# 0.0.0.0:3000     ✗  (would be public — wrong!)
```

### 2. (Optional) Expose only the metrics paths via a host proxy

If you bound to loopback, run a small reverse proxy on the host that forwards
just the metrics paths to the monitoring network. This keeps everything else
invisible even on the monitoring side. Any host-level proxy (nginx, Caddy, etc.)
works — point it at `http://127.0.0.1:3000/metrics`, `http://127.0.0.1:9113/metrics`
and `http://127.0.0.1:9187/metrics`, and deny everything else.

### 3. Configure Prometheus on the monitoring host

Point Prometheus at whatever addresses you exposed in step 1 (or 2). The
exporters serve their metrics at `/metrics` (the default path):

```yaml
scrape_configs:
  - job_name: 'ninerlog-api'
    scrape_interval: 15s
    metrics_path: /metrics
    static_configs:
      - targets: ['10.0.0.5:3000']   # the private address from the override

  - job_name: 'ninerlog-nginx'
    scrape_interval: 15s
    static_configs:
      - targets: ['10.0.0.5:9113']

  - job_name: 'ninerlog-postgres'
    scrape_interval: 15s
    static_configs:
      - targets: ['10.0.0.5:9187']
```

## Available metrics

**API** — see the API's
[metrics reference](https://github.com/fjaeckel/ninerlog-api/blob/main/docs/METRICS.md)
for the full list of exported series (HTTP, auth, database pool, notifications,
email delivery, rate limiting, and Go runtime metrics), plus ready-to-import
Grafana dashboards and Prometheus alerting rules.

**nginx** — the
[nginx-prometheus-exporter](https://github.com/nginxinc/nginx-prometheus-exporter)
exports `stub_status` counters: active/accepted/handled connections, requests,
and the reading/writing/waiting connection states (`nginx_*`). A community
Grafana dashboard is available as ID
[12708](https://grafana.com/grafana/dashboards/12708).

**PostgreSQL** — the
[postgres-exporter](https://github.com/prometheus-community/postgres_exporter)
exports connection counts, transaction/commit/rollback rates, deadlocks, cache
hit ratios, replication lag, and per-database/per-table statistics (`pg_*`).
Grafana dashboard ID
[9628](https://grafana.com/grafana/dashboards/9628) is a good starting point.
