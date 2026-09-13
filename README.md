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
