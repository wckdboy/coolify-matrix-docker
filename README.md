# Matrix on Coolify

Secure, repository-mode Coolify deployment of:

- Synapse `v1.160.0`
- Element Web `v1.12.27`
- Ketesa `v1.5.0`
- PostgreSQL `17.6`

## Deploy

1. In Coolify, create a **Service → Docker Compose** resource from this GitHub repository.
2. Keep the compose path set to `/docker-compose.yaml`.
3. Set `SYNAPSE_SERVER_NAME` **before the first deployment**. This becomes the permanent suffix in Matrix IDs and should not be changed later.
4. Assign HTTPS domains to the parsed components:
   - `synapse:8008` → `https://matrix.example.com`
   - `element:80` → `https://chat.example.com`
   - `ketesa:80` → `https://matrix-admin.example.com`
5. Deploy. Coolify generates and retains the database and initial-admin credentials.

The initial administrator credentials are shown in Coolify as:

- Username: `SERVICE_LOWERCASEUSER_ADMIN`
- Password: `SERVICE_PASSWORD_64_ADMIN`

Open Ketesa and sign in against the Synapse URL with that account.

## Registration

Registration is disabled by default. If `ENABLE_REGISTRATION=true`, it remains token-gated. Create registration tokens in Ketesa; anonymous open registration is never enabled by this stack.

Synapse settings are reconciled at **every** container start, so changing `ENABLE_REGISTRATION` or `MAX_UPLOAD_SIZE` and redeploying takes effect (secrets and signing keys already in the volume are never rotated).

The initial admin account is created through Synapse's shared-secret admin API, which requires `registration_shared_secret`. Coolify generates it as `SERVICE_BASE64_64_REGISTRATION` and the entrypoint writes it into `homeserver.yaml`; without it, no admin can be registered.

## Review notes — 2026-09-13

Fixed in this revision:

1. **No admin user could ever be created.** `register_new_matrix_user` requires `registration_shared_secret`, which Synapse's generated config leaves commented out, and the failure was hidden by `|| true`. The stack now passes a Coolify-generated secret into the config. Without this, Ketesa is unusable.
2. **Mutable settings were first-boot-only.** The config was written once, so later changes to `ENABLE_REGISTRATION` / `MAX_UPLOAD_SIZE` silently did nothing.
3. **Admin-creation errors are now visible** (and "already exists" is distinguished from a real failure) instead of being discarded.

Verify on first deploy:

4. **Element's `config.json` bakes a browser-facing Synapse URL.** With a domain assigned to `synapse:8008`, `SERVICE_URL_SYNAPSE_8008` resolves to the public HTTPS URL; without one it is an internal `http://synapse:8008` the browser cannot reach. Assign the Synapse domain **before** the first deploy, or restart Element after assigning it (its config is rewritten on every start).
5. **`MAX_UPLOAD_SIZE` only governs Synapse.** The proxy in front of it (Coolify/Traefik) has its own body-size limit — raise it to match, or uploads fail at the proxy.
6. Healthchecks assume `curl` in the Synapse image and `wget` in the Element image. Confirm both against the image logs on first run; a healthcheck that cannot execute marks a healthy container unhealthy.
7. Ketesa needs the admin account plus Synapse's admin API reachable over public HTTPS. Keep the Ketesa domain behind Coolify access control or another auth layer.
8. Federation: `SYNAPSE_SERVER_NAME` must match the domain assigned to `synapse:8008`, otherwise serve the `.well-known` files from the root domain (see above), with `Access-Control-Allow-Origin: *` on the client file.
9. Back up **both** named volumes — `synapse-data` holds the signing key, so a database-only backup cannot restore the server's identity.
10. Pinned tags verified to exist on 2026-09-13: `matrixdotorg/synapse:v1.160.0`, `vectorim/element-web:v1.12.27`, `ghcr.io/etkecc/ketesa:v1.5.0`, `postgres:17.6-alpine`.

## Federation

If `SYNAPSE_SERVER_NAME` is the same hostname assigned to Synapse, federation works over HTTPS/443 via Synapse's generated `/.well-known/matrix/server` response.

If you want IDs such as `@user:example.com` while Synapse is hosted at `matrix.example.com`, set `SYNAPSE_SERVER_NAME=example.com` on the **first** deployment and serve these files from the root domain:

`https://example.com/.well-known/matrix/server`

```json
{"m.server":"matrix.example.com:443"}
```

`https://example.com/.well-known/matrix/client`

```json
{"m.homeserver":{"base_url":"https://matrix.example.com"}}
```

The client response must include `Access-Control-Allow-Origin: *`. Test the result with the Matrix Federation Tester after deployment.

## Security and operations

- PostgreSQL is only attached to an internal Docker network and has no published port.
- No service uses host networking, privileged mode, or a Docker socket mount.
- Browser-facing services use `no-new-privileges`; Element also drops all capabilities except the minimal set its nginx startup needs.
- Synapse secrets, signing keys, media, and PostgreSQL data live in named volumes.
- Synapse configuration is generated once. Redeploys do not rotate secrets or overwrite the live configuration.
- Back up both named volumes. A database-only backup is insufficient because the Synapse signing key is in `synapse-data`.
- Image versions are pinned. Review upstream release notes and update deliberately rather than using `latest` in production.

Ketesa requires Synapse's authenticated admin API. Protect the Ketesa domain with Coolify access controls or another authentication layer, and do not share administrator access tokens.
