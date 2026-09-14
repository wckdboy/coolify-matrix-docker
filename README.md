# Matrix on Coolify

Secure, repository-mode Coolify deployment of:

- Synapse `v1.160.0`
- Element Web `v1.12.27`
- Ketesa `v1.5.0`
- PostgreSQL `17.6`

## Deploy — step by step

Do these in order. Steps 1–3 must happen **before** the first deploy; the URLs are
baked into Synapse's config and Element's browser config at deploy time.

1. **Create the resource.** In Coolify: **New Resource → Service → Docker Compose from
   repository** → pick `wckdboy/coolify-matrix-docker`, branch `main`, Compose location
   `/docker-compose.yaml`.
2. **Set the environment variables** (Configuration → Environment Variables). Only these
   are yours to set; everything else is generated:
   - `SYNAPSE_SERVER_NAME` — **required and permanent**. Every Matrix ID ends with it, and
     it cannot be changed after the first deploy without abandoning all accounts. For
     `@user:example.com` with Synapse at `matrix.example.com`, set `example.com` and serve
     the `.well-known` files (see Federation below). For the simple case, set it to the
     same hostname you assign to Synapse in step 3.
   - `SYNAPSE_REPORT_STATS` — `no` (default)
   - `ENABLE_REGISTRATION` — `false` (default)
   - `MAX_UPLOAD_SIZE` — `50M` (default)
   - `POSTGRES_DB` — `synapse` (default)
3. **Assign the domains** (Configuration → General → component cards, or *Domains*):
   - `synapse:8008` → `https://matrix.example.com`
   - `element:80` → `https://chat.example.com`
   - `ketesa:80` → `https://matrix-admin.example.com`
   Coolify issues the certificates. **Assigning these generates the `SERVICE_URL` values
   the stack uses**, so do it before deploying — otherwise Element is built pointing at an
   internal address your browser cannot reach.
4. **Deploy.** Watch the service logs. Expected sequence in the Synapse container:
   `Generating synapse config file` → `Reading registration_shared_secret from /data/...` →
   `[entrypoint] initial admin '<user>' created` → Synapse starts.
5. **Verify.**
   ```
   curl -fsS https://matrix.example.com/health                                  # {}
   curl -fsS https://matrix.example.com/.well-known/matrix/server               # {"m.server":"matrix.example.com:443"}
   curl -fsS -o /dev/null -w '%{http_code}\n' https://chat.example.com          # 200
   curl -fsS -o /dev/null -w '%{http_code}\n' https://matrix-admin.example.com  # 200
   ```
   Then open `chat.example.com`, create an account, and log into Ketesa with the admin
   credentials Coolify shows as `SERVICE_LOWERCASEUSER_ADMIN` / `SERVICE_PASSWORD_64_ADMIN`.
6. **Federation check.** Run your server name through the Matrix Federation Tester.

### If the deploy fails, check these first

| Symptom | Cause | Fix |
|---|---|---|
| Coolify refuses to deploy: "required variable is empty" | `SYNAPSE_SERVER_NAME` not set | Set it (step 2). Coolify blocks deploys while a `:?` variable is empty — this is by design |
| `error while creating mount source path .../scripts/...` | Older revision mounted a repo file that Coolify's deploy directory did not contain | Not possible in this revision: the Synapse entrypoint is inline in the Compose file |
| Containers run but the domains 502 / never get certificates | Custom Docker networks stopped Coolify's proxy from reaching the containers | Not possible in this revision: no custom networks are defined; every service joins Coolify's network and only the declared domains are exposed |
| Element loads but says "can't connect to homeserver" | `base_url` is an internal address (`http://synapse:8008`) because no domain was assigned to `synapse:8008` | Assign the domain, then restart Element (it rewrites `config.json` on every start) |
| No admin account, Ketesa login fails | Registration failed while Synapse was still starting | Check the Synapse logs for `[entrypoint] WARNING: admin creation failed` — the reason is printed now instead of being swallowed |
| Uploads fail with 413 despite `MAX_UPLOAD_SIZE` | The reverse proxy has its own body-size limit | Raise the proxy limit in Coolify to match |

## Registration

Registration is disabled by default. If `ENABLE_REGISTRATION=true`, it remains token-gated
(`registration_requires_token: true`); create the tokens in Ketesa. Anonymous open
registration is never enabled by this stack.

Settings are reconciled on **every** container start, so changing `ENABLE_REGISTRATION` or
`MAX_UPLOAD_SIZE` in Coolify and redeploying takes effect. Secrets are not affected:
Synapse's signing key and its registration/macaroon secrets persist in the `synapse-data`
volume and are never rotated by a redeploy.

## Federation

If `SYNAPSE_SERVER_NAME` equals the hostname assigned to Synapse, federation works over
HTTPS/443 through Synapse's generated `/.well-known/matrix/server` response.

If you want IDs like `@user:example.com` while Synapse is hosted at `matrix.example.com`,
set `SYNAPSE_SERVER_NAME=example.com` on the **first** deployment and serve these files from
the root domain:

`https://example.com/.well-known/matrix/server`

```json
{"m.server":"matrix.example.com:443"}
```

`https://example.com/.well-known/matrix/client`

```json
{"m.homeserver":{"base_url":"https://matrix.example.com"}}
```

The client response must include `Access-Control-Allow-Origin: *`. Test with the Matrix
Federation Tester after deployment.

## Security and operations

- PostgreSQL is not published: it has no ports and is only reachable from the other
  containers on Coolify's network.
- No service uses host networking, privileged mode, or a Docker socket mount.
- Browser-facing services use `no-new-privileges`; Element drops all capabilities except the
  minimal set its nginx startup needs.
- Synapse secrets, signing keys, media, and PostgreSQL data live in named volumes.
- **Back up both volumes.** A database-only backup is insufficient: the Synapse signing key
  lives in `synapse-data`, and losing it means losing the server's identity.
- Image versions are pinned. Review upstream release notes and update deliberately rather
  than following `latest` in production.
- Ketesa requires Synapse's authenticated admin API. Protect the Ketesa domain with Coolify
  access controls or another authentication layer, and do not share administrator access
  tokens.

## Revision history

**2026-09-13 (review + fixes)**

- The Synapse entrypoint is now **inline in the Compose file** instead of a bind-mounted
  `./scripts/synapse-entrypoint.sh`. A missing bind source makes `docker compose up` fail
  before any container starts; Coolify's own service templates inline their entrypoints for
  the same reason.
- **Custom Docker networks removed** (`frontend` / `backend`, one of them `internal: true`).
  Coolify's proxy must share a network with the containers it routes to; Coolify's own
  Matrix template defines no networks. Isolation is preserved because nothing is published
  except the declared domains, and PostgreSQL has no ports.
- URL declarations use the documented bare-list form (`- SERVICE_URL_SYNAPSE_8008`) and the
  public URL is referenced **without** the port suffix, matching Coolify's official template.
- Element resolves the Synapse URL at container start with a fallback
  (`${SYNAPSE_URL_PRIMARY:-${SYNAPSE_URL_FALLBACK}}`), so an empty generated variable can no
  longer produce a broken `config.json`.
- Shell variables inside the inline scripts are `$$`-escaped; without that, Coolify
  interpolates them to empty at parse time and the admin user/password would arrive blank.
- Config reconciliation now happens on **every** boot. Previously the config was written only
  when the volume was empty, so later `ENABLE_REGISTRATION` / `MAX_UPLOAD_SIZE` changes
  silently did nothing.
- Admin-creation failures are printed (with "already exists" distinguished from a real
  failure) instead of being discarded.
- Pinned tags verified to exist: `matrixdotorg/synapse:v1.160.0`,
  `vectorim/element-web:v1.12.27`, `ghcr.io/etkecc/ketesa:v1.5.0`, `postgres:17.6-alpine`.

**Correction to an earlier claim in this file's history:** an earlier review stated that no
admin account could ever be created because `registration_shared_secret` was missing. That
was wrong. `synapse.config.registration` emits `registration_shared_secret` when a config is
generated, and `docker/start.py` persists the registration and macaroon secrets under
`/data/<server>.registration.key` / `<server>.macaroon.key`. The admin registration path was
functional; the real defects were the ones listed above.
