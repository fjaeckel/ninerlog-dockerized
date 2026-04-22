# HTTPS Setup with Let's Encrypt

NinerLog supports automatic HTTPS via Let's Encrypt certificates managed by Certbot.

## Prerequisites

- A domain name pointing to your server's public IP
- Ports 80 and 443 open on your firewall

## Setup

### 1. Configure Domain

```bash
# In .env
TLS_DOMAIN=logbook.example.com
CORS_ORIGIN=https://logbook.example.com
```

### 2. Start the Stack

```bash
docker compose up -d
```

The frontend (nginx) will start on port 80 and serve the ACME challenge path.

### 3. Request Initial Certificate

```bash
docker compose run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d logbook.example.com \
  --agree-tos \
  --email your@email.com
```

### 4. Restart Frontend

```bash
docker compose restart frontend
```

Nginx will now detect the certificate and serve HTTPS on port 443.

## Certificate Renewal

Certbot automatically attempts renewal. To manually trigger:

```bash
docker compose run --rm certbot renew
docker compose restart frontend
```

Certificates are stored in a Docker volume (`letsencrypt_certs`) and persist across container restarts.

## Troubleshooting

### Certificate request fails

- Ensure port 80 is reachable from the internet
- Ensure your DNS `A` record points to this server
- Check Certbot logs: `docker compose logs certbot`

### HTTPS not working after certificate issuance

- Restart the frontend: `docker compose restart frontend`
- Verify the certificate exists: `docker compose exec frontend ls /etc/letsencrypt/live/`

### Mixed content warnings

- Ensure `CORS_ORIGIN` uses `https://`
- Ensure `VITE_API_BASE_URL` is `/api/v1` (relative, not absolute)
