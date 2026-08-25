#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="${SERVER_IP:-109.71.245.162}"
SERVER_USER="${SERVER_USER:-root}"
SERVER_PATH="${SERVER_PATH:-/opt/bobux-server}"
WWW_PATH="${WWW_PATH:-/var/www/bobux}"
ARCHIVE_PATH="/tmp/bobux-server-deploy.tar.gz"
ZIP_PATH="${BOBUX_ZIP_PATH:-dist/Bobux-Windows.zip}"

: "${BOBUX_SERVICE_KEY:?Set BOBUX_SERVICE_KEY before deploying}"

echo "=== Deploying Bobux to ${SERVER_USER}@${SERVER_IP} ==="

tar -czf "${ARCHIVE_PATH}" \
	--exclude='./.git' \
	--exclude='./.godot' \
	--exclude='./exiting_game' \
	--exclude='./launcher_export' \
	--exclude='./dist' \
	--exclude='./tmp_*' \
	--exclude='./node_modules' \
	--exclude='./.env' \
	.

scp "${ARCHIVE_PATH}" "${SERVER_USER}@${SERVER_IP}:/tmp/bobux-server-deploy.tar.gz"
scp "game/launcher/latest.json" "${SERVER_USER}@${SERVER_IP}:/tmp/latest.json"
scp "${ZIP_PATH}" "${SERVER_USER}@${SERVER_IP}:/tmp/Bobux-Windows.zip"
scp "dist/BobuxLauncher-Windows.zip" "${SERVER_USER}@${SERVER_IP}:/tmp/BobuxLauncher-Windows.zip"
scp "ops/vps/deploy_remote.sh" "${SERVER_USER}@${SERVER_IP}:/tmp/deploy_remote.sh"

ssh "${SERVER_USER}@${SERVER_IP}" "BOBUX_API_URL='${BOBUX_API_URL:-http://127.0.0.1:3000/api}' BOBUX_SERVICE_KEY='${BOBUX_SERVICE_KEY}' BOBUX_SERVER_HEARTBEAT_TOKEN='${BOBUX_SERVER_HEARTBEAT_TOKEN:-}' PUBLIC_SERVER_WS_URL='ws://109.71.245.162/ws' bash /tmp/deploy_remote.sh"

echo "=== Done ==="
