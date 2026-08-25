#!/usr/bin/env bash
set -euo pipefail

PB_BIN="${POCKETBASE_BIN:-}"
PB_URL="${POCKETBASE_URL:-http://127.0.0.1:8090}"
PB_EMAIL="${POCKETBASE_SUPERUSER_EMAIL:-admin@bobux.local}"
PB_PASSWORD="${POCKETBASE_SUPERUSER_PASSWORD:-}"
PB_DATA_DIR="${POCKETBASE_DATA_DIR:-}"

GENERATED_PASSWORD="0"
if [ -z "${PB_PASSWORD}" ] || [ "${PB_PASSWORD}" = "change-me" ]; then
	if command -v openssl >/dev/null 2>&1; then
		PB_PASSWORD="$(openssl rand -base64 24 | tr -d '\n' | tr '/+' '_-')"
	else
		PB_PASSWORD="Bobux-$(date +%s)-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo manual-change-required)"
	fi
	GENERATED_PASSWORD="1"
fi

if [ -z "${PB_BIN}" ]; then
	for candidate in /opt/pocketbase/pocketbase /usr/local/bin/pocketbase /usr/bin/pocketbase pocketbase; do
		if command -v "${candidate}" >/dev/null 2>&1 || [ -x "${candidate}" ]; then
			PB_BIN="${candidate}"
			break
		fi
	done
fi

if [ -z "${PB_BIN}" ]; then
	echo "PocketBase binary was not found. Set POCKETBASE_BIN=/path/to/pocketbase." >&2
	exit 1
fi

DIR_ARGS=()
if [ -n "${PB_DATA_DIR}" ]; then
	mkdir -p "${PB_DATA_DIR}"
	DIR_ARGS+=(--dir "${PB_DATA_DIR}")
fi

set +e
UPSERT_OUTPUT="$("${PB_BIN}" superuser upsert "${PB_EMAIL}" "${PB_PASSWORD}" "${DIR_ARGS[@]}" 2>&1)"
UPSERT_STATUS=$?
set -e

if [ "${UPSERT_STATUS}" -ne 0 ]; then
	set +e
	CREATE_OUTPUT="$("${PB_BIN}" superuser create "${PB_EMAIL}" "${PB_PASSWORD}" "${DIR_ARGS[@]}" 2>&1)"
	CREATE_STATUS=$?
	set -e
	if [ "${CREATE_STATUS}" -ne 0 ]; then
		echo "${UPSERT_OUTPUT}" >&2
		echo "${CREATE_OUTPUT}" >&2
		echo "Could not create or update PocketBase superuser." >&2
		exit 1
	fi
else
	echo "${UPSERT_OUTPUT}"
fi

if command -v node >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
	BODY="$(PB_EMAIL="${PB_EMAIL}" PB_PASSWORD="${PB_PASSWORD}" node -e 'process.stdout.write(JSON.stringify({identity: process.env.PB_EMAIL, password: process.env.PB_PASSWORD}))')"
	if curl -fsS -H "Content-Type: application/json" -d "${BODY}" "${PB_URL%/}/api/collections/_superusers/auth-with-password" >/dev/null; then
		echo "PocketBase superuser login verified at ${PB_URL}."
	else
		echo "Superuser was saved, but ${PB_URL} did not accept login yet. Check that PocketBase uses the same --dir/pb_data as this script." >&2
		exit 1
	fi
fi

cat <<EOF

PocketBase admin credentials:
  URL: ${PB_URL%/}/_/
  Public URL: http://admin.109.71.245.162.nip.io/_/
  Login: ${PB_EMAIL}
EOF

if [ "${GENERATED_PASSWORD}" = "1" ]; then
	cat <<EOF
  Password: ${PB_PASSWORD}
EOF
	cat <<'EOF'

Save this password now. It was generated for this run and is not stored in the repository.
To set your own password later, rerun:
  POCKETBASE_SUPERUSER_EMAIL="admin@bobux.local" POCKETBASE_SUPERUSER_PASSWORD="your-new-password" bash /opt/bobux-server/ops/vps/bootstrap_pocketbase_admin.sh
EOF
else
	cat <<'EOF'
  Password: the value from POCKETBASE_SUPERUSER_PASSWORD

Set PRINT_POCKETBASE_PASSWORD=1 only if you intentionally want the script to print the existing password.
EOF
	if [ "${PRINT_POCKETBASE_PASSWORD:-0}" = "1" ]; then
		echo "  Password value: ${PB_PASSWORD}"
	fi
fi
