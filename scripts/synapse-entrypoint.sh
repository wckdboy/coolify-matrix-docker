#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

config=/data/homeserver.yaml

if [[ ! -f "$config" ]]; then
  /start.py generate

  python3 - <<'PY'
import os
from pathlib import Path

import yaml

path = Path("/data/homeserver.yaml")
config = yaml.safe_load(path.read_text())

public_url = os.environ["SERVICE_URL_SYNAPSE_8008"].rstrip("/") + "/"
registration_enabled = os.getenv("ENABLE_REGISTRATION", "false").lower() == "true"

config.update({
    "public_baseurl": public_url,
    "serve_server_wellknown": True,
    "database": {
        "name": "psycopg2",
        "args": {
            "user": os.environ["POSTGRES_USER"],
            "password": os.environ["POSTGRES_PASSWORD"],
            "database": os.environ["POSTGRES_DB"],
            "host": "postgres",
            "port": 5432,
            "cp_min": 5,
            "cp_max": 10,
        },
    },
    "enable_registration": registration_enabled,
    "registration_requires_token": True,
    "allow_public_rooms_without_auth": False,
    "allow_public_rooms_over_federation": False,
    "url_preview_enabled": False,
    "max_upload_size": os.getenv("MAX_UPLOAD_SIZE", "50M"),
    "federation_verify_certificates": True,
})

for listener in config.get("listeners", []):
    if listener.get("type") == "http":
        listener["x_forwarded"] = True
        listener["bind_addresses"] = ["0.0.0.0"]
        listener["resources"] = [{"names": ["client", "federation"], "compress": False}]

path.write_text(yaml.safe_dump(config, sort_keys=False))
PY
fi

create_initial_admin() {
  until curl --fail --silent http://127.0.0.1:8008/health >/dev/null; do
    sleep 2
  done

  register_new_matrix_user \
    --admin \
    --user "$ADMIN_USER" \
    --password "$ADMIN_PASSWORD" \
    --config "$config" \
    http://127.0.0.1:8008 >/dev/null 2>&1 || true
}

create_initial_admin &
exec /start.py
