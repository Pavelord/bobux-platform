#!/usr/bin/env bash
set -euo pipefail

SERVER_PATH="${SERVER_PATH:-/opt/bobux-server}"
WWW_PATH="${WWW_PATH:-/var/www/bobux}"
GODOT_RELEASE_TAG="${GODOT_RELEASE_TAG:-4.7-stable}"
GODOT_ZIP="${GODOT_ZIP:-Godot_v4.7-stable_linux.x86_64.zip}"
GODOT_BIN="${GODOT_BIN:-/usr/local/bin/godot}"
PUBLIC_SERVER_WS_URL="${PUBLIC_SERVER_WS_URL:-ws://109.71.245.162/ws}"
BOBUX_API_URL="${BOBUX_API_URL:-http://127.0.0.1:3000/api}"
BOBUX_SERVICE_KEY="${BOBUX_SERVICE_KEY:-}"
BOBUX_SERVER_HEARTBEAT_TOKEN="${BOBUX_SERVER_HEARTBEAT_TOKEN:-}"

if [ -z "${BOBUX_SERVICE_KEY}" ]; then
	echo "BOBUX_SERVICE_KEY must be provided through the protected server environment." >&2
	exit 1
fi

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl unzip nginx nodejs rsync \
	libasound2t64 libfontconfig1 libgl1 libx11-6 libxcursor1 libxi6 libxinerama1 \
	libxkbcommon0 libxrandr2 libxrender1 libxext6 libxfixes3 \
	libwayland-client0 libwayland-cursor0 libwayland-egl1

if ! command -v pm2 >/dev/null 2>&1; then
	npm install -g pm2
fi

if [ ! -x "${GODOT_BIN}" ] || ! "${GODOT_BIN}" --version | grep -q "4.7"; then
	curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${GODOT_RELEASE_TAG}/${GODOT_ZIP}" -o /tmp/godot.zip
	rm -rf /opt/godot
	mkdir -p /opt/godot
	unzip -q /tmp/godot.zip -d /opt/godot
	mv "/opt/godot/Godot_v4.7-stable_linux.x86_64" "${GODOT_BIN}"
	chmod +x "${GODOT_BIN}"
	rm -f /tmp/godot.zip
fi

mkdir -p "${SERVER_PATH}" "${WWW_PATH}/launcher" "${WWW_PATH}/downloads" /var/log/bobux
tar -xzf /tmp/bobux-server-deploy.tar.gz -C "${SERVER_PATH}"
cp "${SERVER_PATH}/ops/vps/index.html" "${WWW_PATH}/index.html"
cp "${SERVER_PATH}/ops/vps/admin.html" "${WWW_PATH}/admin.html"
cp /tmp/latest.json "${WWW_PATH}/launcher/latest.json"
cp /tmp/latest.json "${WWW_PATH}/downloads/latest.json"
cp /tmp/Bobux-Windows.zip "${WWW_PATH}/downloads/Bobux-Windows.zip"
if [ -f /tmp/BobuxLauncher-Windows.zip ]; then
	cp /tmp/BobuxLauncher-Windows.zip "${WWW_PATH}/downloads/BobuxLauncher-Windows.zip"
fi
WWW_PATH="${WWW_PATH}" node --input-type=commonjs <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const manifest = JSON.parse(fs.readFileSync('/tmp/latest.json', 'utf8'));
const downloadsDir = path.join(process.env.WWW_PATH || '/var/www/bobux', 'downloads');
function mirrorVersioned(url, sourceFile) {
	if (!url || !fs.existsSync(sourceFile)) return;
	let fileName = '';
	try {
		fileName = path.basename(new URL(url).pathname);
	} catch {
		fileName = path.basename(String(url));
	}
	if (!fileName || fileName === path.basename(sourceFile)) return;
	fs.copyFileSync(sourceFile, path.join(downloadsDir, fileName));
	console.log(`Mirrored ${path.basename(sourceFile)} as ${fileName}`);
}
mirrorVersioned(manifest.zip_url, path.join(downloadsDir, 'Bobux-Windows.zip'));
if (manifest.launcher) {
	mirrorVersioned(manifest.launcher.zip_url, path.join(downloadsDir, 'BobuxLauncher-Windows.zip'));
}
NODE
cp "${SERVER_PATH}/ops/vps/bobux_nginx.conf" /etc/nginx/sites-available/bobux
ln -sf /etc/nginx/sites-available/bobux /etc/nginx/sites-enabled/bobux
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

if [ -d "${SERVER_PATH}/services/bobux_api" ]; then
	mkdir -p /opt/bobux-api
	rsync -a --delete --exclude='.env' --exclude='node_modules' "${SERVER_PATH}/services/bobux_api/" /opt/bobux-api/
	if [ ! -f /opt/bobux-api/.env ]; then
		cp /opt/bobux-api/.env.example /opt/bobux-api/.env
	fi
	cd /opt/bobux-api
	npm install --omit=dev
	pm2 delete bobux-api 2>/dev/null || true
	set -a
	. /opt/bobux-api/.env
	set +a
	if [ -n "${POCKETBASE_SUPERUSER_EMAIL:-}" ] && [ -n "${POCKETBASE_SUPERUSER_PASSWORD:-}" ] && [ "${POCKETBASE_SUPERUSER_PASSWORD:-}" != "change-me" ]; then
		if bash "${SERVER_PATH}/ops/vps/bootstrap_pocketbase_admin.sh"; then
			echo "PocketBase admin user is ready."
		else
			echo "WARNING: PocketBase admin bootstrap failed. Check POCKETBASE_BIN, POCKETBASE_DATA_DIR and PocketBase service status." >&2
		fi
	else
		echo "WARNING: PocketBase superuser credentials are not configured in /opt/bobux-api/.env." >&2
	fi
	pm2 start /opt/bobux-api/server.js --name bobux-api --update-env
fi

cd "${SERVER_PATH}"
"${GODOT_BIN}" --headless --import --path "${SERVER_PATH}" || true

pm2 delete bobux 2>/dev/null || true
PUBLIC_SERVER_WS_URL="${PUBLIC_SERVER_WS_URL}" \
GODOT_SERVER_PORT="9000" \
GODOT_SERVER_MAP="classic" \
BOBUX_API_URL="${BOBUX_API_URL}" \
BOBUX_SERVICE_KEY="${BOBUX_SERVICE_KEY}" \
BOBUX_SERVER_HEARTBEAT_TOKEN="${BOBUX_SERVER_HEARTBEAT_TOKEN}" \
pm2 start "${GODOT_BIN}" --name bobux -- \
	--output /var/log/bobux/godot.log \
	--error /var/log/bobux/godot.err.log \
	--headless --path "${SERVER_PATH}" --script res://server/server_main.gd

sleep 2
curl -fsS http://127.0.0.1/launcher/latest.json >/dev/null
curl -fsS http://127.0.0.1:3000/api/health | grep -q '"ok":true'
curl -fsS http://127.0.0.1/api/health | grep -q '"ok":true'
AUTH_CODE="$(curl -sS -o /dev/null -w '%{http_code}' \
	-H 'Content-Type: application/json' \
	-d '{"email":"bobux-healthcheck@example.invalid","password":"bad-password"}' \
	'http://127.0.0.1/api/auth/v1/token?grant_type=password' || echo 000)"
case "${AUTH_CODE}" in
	200|400|401|422|429) echo "Auth route reachable (${AUTH_CODE})." ;;
	*) echo "Auth route failed (${AUTH_CODE})." >&2; exit 1 ;;
esac

pm2 save

echo "Deploy complete."
