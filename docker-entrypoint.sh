#!/usr/bin/env bash
set -euo pipefail

export GODOT_SERVER_PORT="${GODOT_SERVER_PORT:-9000}"
export GODOT_SERVER_MAP="${GODOT_SERVER_MAP:-classic}"
export APP_PORT="${PORT:-7860}"

LOG_FILE="/tmp/godot-server.log"
TAIL_PID=""
NGINX_PID=""

touch "${LOG_FILE}"
rm -f /run/nginx.pid /tmp/nginx.pid

if [[ -f /etc/nginx/nginx.conf ]]; then
	sed -i "s/listen 7860;/listen ${APP_PORT};/g" /etc/nginx/nginx.conf
fi

/usr/local/bin/godot --headless --path /app --script res://server/server_main.gd >> "${LOG_FILE}" 2>&1 &
GODOT_PID=$!

tail -n +1 -F "${LOG_FILE}" &
TAIL_PID=$!

cleanup() {
	set +e
	for pid in "${NGINX_PID}" "${GODOT_PID}" "${TAIL_PID}"; do
		if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
			kill "${pid}" 2>/dev/null || true
		fi
	done
	wait "${GODOT_PID}" 2>/dev/null || true
	wait "${NGINX_PID}" 2>/dev/null || true
	wait "${TAIL_PID}" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

sleep 4
if ! kill -0 "${GODOT_PID}" 2>/dev/null; then
	echo "[entrypoint] Godot server exited during startup."
	cat "${LOG_FILE}" || true
	exit 1
fi

nginx -g 'daemon off;' &
NGINX_PID=$!

while true; do
	if ! kill -0 "${GODOT_PID}" 2>/dev/null; then
		echo "[entrypoint] Godot server stopped unexpectedly."
		cat "${LOG_FILE}" || true
		exit 1
	fi
	if ! kill -0 "${NGINX_PID}" 2>/dev/null; then
		echo "[entrypoint] Nginx stopped unexpectedly."
		exit 1
	fi
	sleep 5
done
