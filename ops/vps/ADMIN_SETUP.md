# Bobux Admin Setup

The public admin page is served from `/admin.html` and talks to:

- `POST /api/admin/login`
- `GET /api/admin/stats`

The login is a PocketBase `_superusers` login. Do not commit real passwords.

There are two admin surfaces:

- `http://109.71.245.162/admin.html` - Bobux overview dashboard with live counters.
- `http://admin.109.71.245.162.nip.io/_/` - the real PocketBase Admin UI where you can edit collections, users, maps, catalog items and files.

## Create the PocketBase superuser

Current Bobux admin credentials:

```text
URL: http://admin.109.71.245.162.nip.io/_/
Login: admin@bobux.local
Password: use the value stored in `POCKETBASE_SUPERUSER_PASSWORD`; never commit it.
```

Fast reset from Windows:

```powershell
powershell -ExecutionPolicy Bypass -File C:\robloxclone\ops\vps\reset_pocketbase_admin_password.ps1
```

Full admin panel deploy from Windows also resets the password to the same value:

```powershell
powershell -ExecutionPolicy Bypass -File C:\robloxclone\ops\vps\deploy_admin_panel.ps1
```

Fast path on the VPS:

```bash
POCKETBASE_SUPERUSER_EMAIL="admin@bobux.local" POCKETBASE_SUPERUSER_PASSWORD="<secure-password>" bash /opt/bobux-server/ops/vps/bootstrap_pocketbase_admin.sh
```

The script creates or updates `admin@bobux.local`, verifies login against PocketBase, and prints the credentials.

To choose your own password:

```bash
export POCKETBASE_SUPERUSER_EMAIL="admin@bobux.local"
export POCKETBASE_SUPERUSER_PASSWORD="use-a-long-real-password"
export POCKETBASE_URL="http://127.0.0.1:8090"
export POCKETBASE_DATA_DIR="/opt/pocketbase/pb_data"
bash /opt/bobux-server/ops/vps/bootstrap_pocketbase_admin.sh
```

If PocketBase is installed somewhere unusual, also set:

```bash
export POCKETBASE_BIN="/opt/pocketbase/pocketbase"
```

PocketBase documents the first superuser flow and the `superuser create EMAIL PASS` / `superuser upsert EMAIL PASS` CLI commands in its official docs.

## Nginx routing

`ops/vps/bobux_nginx.conf` exposes PocketBase on a separate wildcard DNS host:

```text
http://admin.109.71.245.162.nip.io/_/
```

This matters because PocketBase Admin expects its own root `/api/*` paths. The main Bobux game API already owns `http://109.71.245.162/api/*`, so the PocketBase console must be on a separate host instead of `/pocketbase` on the same host.

## Deploy behavior

`ops/vps/deploy_remote.sh` now copies:

- `ops/vps/index.html` to `/var/www/bobux/index.html`
- `ops/vps/admin.html` to `/var/www/bobux/admin.html`

If `/opt/bobux-api/.env` contains real `POCKETBASE_SUPERUSER_*` values, deploy also attempts to bootstrap and verify the PocketBase superuser before starting `bobux-api`.
