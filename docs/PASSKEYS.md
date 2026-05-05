# Enabling Passkeys (WebAuthn)

NinerLog supports passwordless sign-in via [WebAuthn](https://www.w3.org/TR/webauthn-2/) /
[passkeys](https://fidoalliance.org/passkeys/). Once enabled, users can register one or more
authenticators (Touch ID, Face ID, Windows Hello, a YubiKey, an Android phone via QR code, …)
from the **Profile → Account** page and sign in with that authenticator instead of a password.

Passkeys are **opt-in** at the deployment level. They are disabled by default — set
`WEBAUTHN_RP_ID` in your `.env` to turn them on.

---

## Prerequisites

WebAuthn is a browser-platform feature with strict requirements you must satisfy before
passkeys will work end-to-end:

1. **HTTPS or localhost.** Browsers expose `window.PublicKeyCredential` only in
   [secure contexts](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts).
   In practice this means:
   - `https://yourdomain.com` ✅
   - `http://localhost` / `http://127.0.0.1` ✅
   - `http://yourdomain.com` ❌ (passkeys will not be available)

   If you have not yet set up TLS, see [HTTPS.md](HTTPS.md) first.

2. **A registrable, multi-label domain for `RP_ID`.** The Relying-Party ID must be either
   the exact host the user visits or a registrable parent of it. Single-label hostnames
   (e.g. `logbook`, `ninerlog-dev`) are rejected by the WebAuthn spec.
   - User visits `https://logbook.example.com` → `RP_ID=logbook.example.com` ✅ or `RP_ID=example.com` ✅
   - User visits `https://logbook.example.com` → `RP_ID=other.example.com` ❌

3. **`RP_ORIGINS` must list every origin the user might visit**, including scheme and
   non-default port. If you serve both `https://logbook.example.com` and a www variant,
   include both.

---

## Configuration

Add the following to your `.env`:

```bash
# Required to enable passkeys
WEBAUTHN_RP_ID=logbook.example.com

# Optional — shown in the OS / browser passkey UI
WEBAUTHN_RP_NAME=NinerLog

# Comma-separated list of full origins. Defaults to CORS_ORIGIN if unset.
WEBAUTHN_RP_ORIGINS=https://logbook.example.com
```

Then restart the API container so it picks up the new environment:

```bash
docker compose up -d api
```

You should see one of these lines in `docker compose logs api`:

```
✅ WebAuthn enabled (RP ID: logbook.example.com)
```

If you see `ℹ️ WebAuthn disabled (set WEBAUTHN_RP_ID to enable)`, the variable did not
reach the container — confirm `.env` is in the same directory as `docker-compose.yml`
and that you restarted the service.

If you see `⚠️ WebAuthn disabled: ...`, the WebAuthn library rejected your config — see
[Troubleshooting](#troubleshooting) below.

---

## How users enable passkeys

Once the server has WebAuthn enabled, users can self-serve from the UI:

1. Sign in with email + password as usual.
2. Open **Profile** → **Account** tab.
3. Under **Passkeys**, type a label (e.g. _MacBook Touch ID_) and click **Add passkey**.
4. The browser/OS prompts for biometric or PIN confirmation.
5. The passkey appears in the list and can be used immediately on the sign-in page via
   the **Sign in with a passkey** button.

Each user can register multiple passkeys (e.g. one per device) and revoke any of them at
any time from the same screen.

---

## Common deployment scenarios

### Single domain, HTTPS

Most installations.

```bash
TLS_DOMAIN=logbook.example.com
CORS_ORIGIN=https://logbook.example.com

WEBAUTHN_RP_ID=logbook.example.com
WEBAUTHN_RP_NAME=NinerLog
WEBAUTHN_RP_ORIGINS=https://logbook.example.com
```

### Apex + www

If you serve both `example.com` and `www.example.com`, use the apex as `RP_ID` so passkeys
work on either origin:

```bash
WEBAUTHN_RP_ID=example.com
WEBAUTHN_RP_ORIGINS=https://example.com,https://www.example.com
```

### Local development on `http://localhost`

`localhost` is treated as a secure context, so passkeys work without TLS:

```bash
CORS_ORIGIN=http://localhost
WEBAUTHN_RP_ID=localhost
WEBAUTHN_RP_ORIGINS=http://localhost,http://localhost:5173
```

### Disabling passkeys

Leave `WEBAUTHN_RP_ID` empty (or remove it). The `/auth/webauthn/*` endpoints will return
`503 Service Unavailable` and the UI will hide the passkey controls.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| API logs `⚠️ WebAuthn disabled: field 'RPID' is not a valid domain string` | `WEBAUTHN_RP_ID` is a single-label hostname like `localhost-dev` | Use a multi-label domain or plain `localhost` |
| Browser shows `The relying party ID is not a registrable domain suffix of the effective domain` | `RP_ID` doesn't match (or isn't a parent of) the host the user visits | Set `RP_ID` to the exact visited host, or its registrable parent |
| `Sign in with a passkey` button doesn't appear, or `Add passkey` is disabled | Site is served over plain `http://` on a non-loopback host | Enable HTTPS — see [HTTPS.md](HTTPS.md) |
| `The origin is not allowed` | Origin used by the browser is missing from `WEBAUTHN_RP_ORIGINS` | Add it (full scheme + host + port) and restart the API |
| `/api/v1/auth/webauthn/*` returns `503` | `WEBAUTHN_RP_ID` is empty | Set it in `.env` and `docker compose up -d api` |

---

## Security notes

- Passkeys are stored as public-key credentials in PostgreSQL. The server never sees a
  shared secret — only the public key, the credential ID, and a monotonically increasing
  sign-counter.
- The sign-counter is checked on every assertion; a regression triggers an authentication
  failure (cloned-authenticator detection).
- WebAuthn does **not** replace 2FA — it _is_ a stronger second factor on its own, but
  password-based 2FA (TOTP) remains available and independent.
- Revoking a passkey deletes the credential record server-side; the user's authenticator
  may still display a stale entry until they remove it locally.

---

## See also

- [`CONFIGURATION.md`](CONFIGURATION.md) — full env-var reference
- [`HTTPS.md`](HTTPS.md) — TLS / Let's Encrypt setup
- [WebAuthn Guide (webauthn.guide)](https://webauthn.guide/) — protocol primer
