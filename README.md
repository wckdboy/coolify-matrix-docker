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
   - `SYNAPSE_PUBLIC_URL` — **required**. The public HTTPS URL of Synapse, e.g.
     `https://matrix.example.com`. This is what Synapse advertises and what Element points
     at. It must be an absolute URL with the scheme and no trailing slash.
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
| `warning: The "SERVICE_URL_SYNAPSE_8008" variable is not set. Defaulting to a blank string.` | A cross-service reference to a Coolify URL/FQDN variable. Coolify populates `SERVICE_URL_*` / `SERVICE_FQDN_*` **only in the service that declares them**; password and username variables are global, URLs are not | Fixed in this revision: nothing references another service's URL variable. The public URL is passed as the plain `SYNAPSE_PUBLIC_URL` setting instead |
| `Deployment failed: Command execution failed (exit code 1): ... docker compose ... up -d` | Look at the compose output **above** that line in the Coolify log — it is always one of the rows below | Read the first error line, do not guess |
| `required variable SYNAPSE_PUBLIC_URL is missing a value` (exit 1) | The variable is required and not set in Coolify | Add `SYNAPSE_PUBLIC_URL=https://matrix.yourdomain.com` under Environment Variables and redeploy |
| `dependency failed to start: container ... is unhealthy` | A container's healthcheck failed while `up -d` waited on it. First boot runs DB migrations, which can exceed a short healthcheck window | Fixed in this revision: Synapse gets `start_period: 180s` / `retries: 20`, and Element + Ketesa wait for `service_started` instead of `service_healthy` |
| `PermissionError: [Errno 13] Permission denied: '/data/<server>.log.config'` (Synapse exits during initialisation) | The entrypoint created the config as **root** with a restrictive umask, then Synapse's image dropped privileges to the `synapse` user (991:991), which could not read root-owned `0600` files | Fixed in this revision: `umask 022` and an explicit `chown -R 991:991 /data` + `chmod -R a+rX /data` before the server starts (also repairs root-owned leftovers from earlier failed deploys) |
| `/bin/sh: can't create /app/config.json: Permission denied` (Element) | The element-web image runs as `USER nginx` with a root-owned `/app`, so it cannot write its own config | Fixed in this revision: the Element container runs as `0:0` so the config can be generated at startup (nginx's master drops worker processes to `nginx` itself). Alternative: mount a read-only `config.json` at `/app/config.json` and remove `user: "0:0"` |
| `pull access denied` / `manifest unknown` | The host could not pull an image | Confirm the pinned tags are reachable from the server (`docker pull ghcr.io/etkecc/ketesa:v1.5.0` on the host) |
| `error while creating mount source path .../scripts/...` | Older revision mounted a repo file that Coolify's deploy directory did not contain | Not possible in this revision: the Synapse entrypoint is inline in the Compose file |
| Containers run but the domains 502 / never get certificates | Custom Docker networks stopped Coolify's proxy from reaching the containers | Not possible in this revision: no custom networks are defined; every service joins Coolify's network and only the declared domains are exposed |
| Element loads but says "can't connect to homeserver" | `base_url` is wrong or empty | `SYNAPSE_PUBLIC_URL` must be the public HTTPS URL with the scheme, e.g. `https://matrix.example.com`; if it is empty Element exits at start and says so |
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
- **Image policy: floating tags.** Synapse, Element and Ketesa track `latest`; PostgreSQL
  floats within major 17 (`postgres:17-alpine`).
  - Coolify does **not** re-pull floating tags on its own: after an upstream release, redeploy
    with a fresh pull (Coolify's *Redeploy without cache*, or `docker compose pull` on the
    host followed by a redeploy) to actually move versions.
  - A Synapse update runs its own database migrations on the next boot, so the first start
    after an update takes longer — that is what the 180 s healthcheck start period is for.
  - PostgreSQL is deliberately **not** on `latest`: a major-version jump (18, 19, …) against an
    existing data directory makes Postgres refuse to start and can cost you the homeserver
    database. Move the major only together with a dump/restore or `pg_upgrade`.
  - If an upstream release ever breaks the stack, pin that one image back to a specific tag
    (e.g. `matrixdotorg/synapse:v1.160.0`) and redeploy.
- Ketesa requires Synapse's authenticated admin API. Protect the Ketesa domain with Coolify
  access controls or another authentication layer, and do not share administrator access
  tokens.

## Revision history

**2026-09-14 (floating image tags)**

- Synapse, Element and Ketesa now track `latest` (user request); PostgreSQL floats within
  major 17. Previously all four were pinned to exact versions.
- Verified before switching: `matrixdotorg/synapse:latest` (a newer build than `v1.160.0`),
  `vectorim/element-web:latest`, `ghcr.io/etkecc/ketesa:latest` and `postgres:17-alpine` all
  exist and pull.
- Because Coolify does not re-pull floating tags by itself, updating now requires an explicit
  redeploy with a fresh pull; see the operations section.

**2026-09-14 (Element fix + verified image facts)**

- `/bin/sh: can't create /app/config.json: Permission denied` — `vectorim/element-web:v1.12.27`
  is built with `USER nginx` and a root-owned `/app`, so the container cannot write its own
  `config.json`. The image is designed for a **mounted** config. This stack generates it at
  startup instead, so the Element service now runs as `0:0`: nginx's master process then drops
  the worker processes to `nginx` exactly as it does in the default configuration.
  If you prefer no root process, mount a read-only `config.json` at `/app/config.json` and
  delete the `user: "0:0"` line.
- Element's health check now probes `/config.json`, matching the check the image itself ships
  (it is a real test that the generated config is being served, rather than just that nginx
  answers).
- Verified from the image config, so it is not a guess: the effective listen port is
  `ELEMENT_WEB_PORT=80`, which is what `SERVICE_URL_ELEMENT_80` routes to. The `8080/tcp` in
  the image metadata is stale and unused.

**2026-09-14 (permissions fix)**

- `PermissionError: [Errno 13] Permission denied: '/data/doom.moe.log.config'` — Synapse's image
  runs the entrypoint as **root**, then drops privileges to the `synapse` user (991:991) to run
  the server. The entrypoint set `umask 077`, so the generated config files were root-owned and
  mode `0600`: the unprivileged server process could not read them, and the container died during
  initialisation.
- Fix: `umask 022`, plus an explicit `chown -R 991:991 /data` and `chmod -R a+rX /data` before
  `exec /start.py`. The recursive repair also cleans up root-owned leftovers from earlier failed
  deployments, which is why it runs on every boot rather than only on a fresh volume.

**2026-09-14 (deploy hardening)**

- Synapse's healthcheck window raised to `start_period: 180s`, `retries: 20`. The first boot
  runs database migrations; a short window marks a healthy container unhealthy, and because
  `docker compose up -d` waits on health conditions, that fails the whole deployment with
  exit code 1.
- Element and Ketesa now wait for `service_started` instead of `service_healthy`. They do not
  need Synapse to be ready (they only render a config and start nginx), and gating them on
  health made a slow Synapse fail the deployment.
- Both failure modes above were reproduced locally against the exact command Coolify runs
  (`docker compose --env-file ... --project-directory ... -f ... config/up -d`) before being
  documented.

**2026-09-14 (deploy warning fix)**

- Removed the last cross-service reference to a Coolify URL variable. Element's environment
  interpolated `${SERVICE_URL_SYNAPSE_8008}` while only Synapse declares it, so Coolify
  produced `The "SERVICE_URL_SYNAPSE_8008" variable is not set. Defaulting to a blank string.`
  and Element would have been configured with an empty homeserver URL. URL/FQDN variables are
  scoped to the declaring service (password and username variables are not).
- Added a required `SYNAPSE_PUBLIC_URL` setting: the public HTTPS URL of Synapse, used by both
  Synapse (`public_baseurl`) and Element (`base_url`). Deployment is blocked while it is empty,
  so a blank URL can no longer reach a running container.
- Element now fails fast with an explicit message if that value is empty.

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
