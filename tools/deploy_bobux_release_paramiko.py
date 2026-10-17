#!/usr/bin/env python3
"""Upload an already validated Bobux release and switch manifests atomically."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import posixpath
import re
import shlex
import stat
import sys
import time
import zipfile
from pathlib import Path

import paramiko


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def require_file(path: Path, minimum_bytes: int) -> None:
    if not path.is_file() or path.stat().st_size < minimum_bytes:
        raise RuntimeError(f"Missing or undersized release artifact: {path}")


def upload_atomic(
    sftp: paramiko.SFTPClient,
    local_path: Path,
    remote_path: str,
) -> None:
    temporary_path = f"{remote_path}.uploading"
    size = local_path.stat().st_size
    last_report = -1

    def report(transferred: int, total: int) -> None:
        nonlocal last_report
        percent = int((transferred * 100) / max(total, 1))
        bucket = percent // 10
        if bucket != last_report:
            last_report = bucket
            print(
                f"  {local_path.name}: {percent:3d}% "
                f"({transferred / 1048576:.1f}/{size / 1048576:.1f} MiB)",
                flush=True,
            )

    try:
        sftp.remove(temporary_path)
    except FileNotFoundError:
        pass
    sftp.put(str(local_path), temporary_path, callback=report, confirm=True)
    try:
        sftp.remove(remote_path)
    except FileNotFoundError:
        pass
    sftp.rename(temporary_path, remote_path)


def run_remote(
    client: paramiko.SSHClient,
    command: str,
    *,
    timeout: int = 900,
) -> str:
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    stdin.close()
    while not stdout.channel.exit_status_ready():
        line = stdout.readline()
        if line:
            print(line.rstrip(), flush=True)
        else:
            time.sleep(0.05)
    remaining_stdout = stdout.read().decode("utf-8", errors="replace")
    remaining_stderr = stderr.read().decode("utf-8", errors="replace")
    if remaining_stdout:
        print(remaining_stdout.rstrip(), flush=True)
    exit_code = stdout.channel.recv_exit_status()
    if remaining_stderr:
        print(remaining_stderr.rstrip(), file=sys.stderr, flush=True)
    if exit_code != 0:
        raise RuntimeError(f"Remote command failed with exit code {exit_code}")
    return remaining_stdout


def shell_quote(value: str) -> str:
    return shlex.quote(value)


def sync_remote_ai_environment(sftp: paramiko.SFTPClient) -> bool:
    """Update server-only AI settings without exposing values in commands/logs."""
    api_key = os.environ.get("BOBUX_AI_API_KEY", "").strip()
    if not api_key:
        return False
    folder_id = os.environ.get("BOBUX_AI_FOLDER_ID", "").strip()
    safe_value = re.compile(r"^[A-Za-z0-9_.-]+$")
    if safe_value.fullmatch(api_key) is None:
        raise RuntimeError("BOBUX_AI_API_KEY contains unsupported dotenv characters.")
    if folder_id and safe_value.fullmatch(folder_id) is None:
        raise RuntimeError("BOBUX_AI_FOLDER_ID contains unsupported dotenv characters.")

    remote_path = "/opt/bobux-api/.env"
    temporary_path = f"{remote_path}.uploading"
    try:
        with sftp.open(remote_path, "r") as source:
            existing = source.read().decode("utf-8", errors="replace")
    except FileNotFoundError:
        existing = ""

    # A game release must preserve the live provider configuration. CI secrets
    # may predate a provider/model change made by the owner on the server.
    if re.search(r"^BOBUX_AI_API_KEY=.+$", existing, re.MULTILINE) and os.environ.get("BOBUX_SYNC_AI_ENVIRONMENT") != "1":
        return False

    is_gemini = api_key.startswith("AIza")
    values = {
        "BOBUX_AI_API_KEY": api_key,
        "BOBUX_AI_PROVIDER": "gemini" if is_gemini else "yandex",
        "BOBUX_AI_FOLDER_ID": folder_id,
        "BOBUX_AI_MODEL": "gemini-3.6-flash" if is_gemini else "",
        "BOBUX_AI_BASE_URL": "",
    }
    retained = [
        line for line in existing.splitlines()
        if line.split("=", 1)[0].strip() not in values
    ]
    retained.extend(f"{name}={value}" for name, value in values.items())
    payload = ("\n".join(retained).rstrip() + "\n").encode("utf-8")
    with sftp.open(temporary_path, "w") as destination:
        destination.write(payload)
    sftp.chmod(temporary_path, stat.S_IRUSR | stat.S_IWUSR)
    try:
        sftp.remove(remote_path)
    except FileNotFoundError:
        pass
    sftp.rename(temporary_path, remote_path)
    return True


def build_remote_script(
    *,
    version: str,
    build: int,
    mobile_version: str,
    mobile_build: int,
    remote_root: str,
    web_root: str,
    hashes: dict[str, str],
) -> str:
    q = shell_quote
    versioned_windows = f"Bobux-Windows-{version}-build{build}.zip"
    versioned_mobile = f"Bobux-Android-{mobile_version}-build{mobile_build}.apk"
    return f"""#!/usr/bin/env bash
set -Eeuo pipefail

REMOTE_ROOT={q(remote_root)}
WEB_ROOT={q(web_root)}
VERSIONED_WINDOWS={q(versioned_windows)}
VERSIONED_MOBILE={q(versioned_mobile)}
NODE_BIN=/opt/bobux-runtime/node/bin/node
if [ ! -x "$NODE_BIN" ]; then NODE_BIN=$(command -v node); fi
# Refuse to replace the working API with a build its runtime cannot import.
"$NODE_BIN" -e "require('node:sqlite'); console.log('SQLite runtime available')"

echo "=== Bobux atomic deploy {q(version)} build {build} ==="
echo "{hashes['hotfix']}  /tmp/bobux-hotfix.tar.gz" | sha256sum -c -
echo "{hashes['windows']}  /tmp/$VERSIONED_WINDOWS" | sha256sum -c -
echo "{hashes['launcher']}  /tmp/BobuxLauncher-Windows.zip" | sha256sum -c -
echo "{hashes['mobile']}  /tmp/$VERSIONED_MOBILE" | sha256sum -c -

echo "{hashes['setup']}  /tmp/BobuxSetup.exe" | sha256sum -c -
echo "{hashes['linux']}  /tmp/Bobux-Linux-x86_64.tar.gz" | sha256sum -c -
echo "{hashes['desktop']}  /tmp/desktop-latest.json" | sha256sum -c -
# Run the actual exported Linux binary before touching the running services.
LINUX_SMOKE=$(mktemp -d /tmp/bobux-linux-smoke.XXXXXX)
STAGE=$(mktemp -d "$REMOTE_ROOT.release-stage.XXXXXX")
BACKUP="/opt/bobux-release-rollback-{build}-$(date -u +%Y%m%dT%H%M%SZ)"
RUNTIME_CHANGED=0
TRANSACTION_HELPER="$STAGE/tools/server_release_transaction.py"
cleanup() {{
  case "$LINUX_SMOKE" in /tmp/bobux-linux-smoke.*) rm -rf -- "$LINUX_SMOKE";; esac
  case "$STAGE" in "$REMOTE_ROOT.release-stage."*) rm -rf -- "$STAGE";; esac
}}
rollback() {{
  status=$?
  trap - ERR
  if [ "$RUNTIME_CHANGED" = 1 ]; then
    echo "Release failed; restoring the previous release from $BACKUP." >&2
    pm2 stop bobux bobux-api >/dev/null 2>&1 || true
    if python3 "$TRANSACTION_HELPER" restore --backup "$BACKUP"; then
      "$GODOT_BIN" --headless --editor --import --quit --path "$REMOTE_ROOT" >"$BACKUP/rollback-import.log" 2>&1 || true
      nginx -t && systemctl reload nginx || true
      cd /opt/bobux-api
      set -a
      . /opt/bobux-api/.env
      set +a
      pm2 restart bobux-api bobux --update-env >/dev/null || true
      pm2 save >/dev/null || true
    else
      echo "Automatic file rollback failed. Snapshot retained at $BACKUP." >&2
    fi
  fi
  exit "$status"
}}
trap cleanup EXIT
trap rollback ERR
tar -xzf /tmp/Bobux-Linux-x86_64.tar.gz -C "$LINUX_SMOKE"
(cd "$LINUX_SMOKE/Bobux" && timeout 90 ./Bobux.x86_64 --headless -- --verify-lua-runtime) > "$LINUX_SMOKE/smoke.log" 2>&1 || {{ tail -n 30 "$LINUX_SMOKE/smoke.log"; exit 1; }}
grep -q BOBUX_LUA_SMOKE_OK "$LINUX_SMOKE/smoke.log"
echo 'Linux exported Lua smoke passed'
python3 "$LINUX_SMOKE/build_appimage.py" "$LINUX_SMOKE" /tmp
# Both exported Linux smoke checks have completed. Release their generated
# extraction before staging the server and its rollback snapshot.
case "$LINUX_SMOKE" in /tmp/bobux-linux-smoke.*) rm -rf -- "$LINUX_SMOKE";; esac

# Import and test the exact staged runtime before stopping either live service.
tar -xzf /tmp/bobux-hotfix.tar.gz -C "$STAGE"
python3 "$STAGE/tools/validate_server_release_archive.py" /tmp/bobux-hotfix.tar.gz
GODOT_BIN=/usr/local/bin/godot
test -x "$GODOT_BIN"
if ! "$GODOT_BIN" --headless --editor --import --quit --path "$STAGE" >"$STAGE/preflight-import.log" 2>&1; then
  tail -n 50 "$STAGE/preflight-import.log" >&2
  exit 1
fi
if grep -Eq 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$STAGE/preflight-import.log"; then
  echo 'Godot staged server preflight failed; live services are unchanged.' >&2
  tail -n 50 "$STAGE/preflight-import.log" >&2
  exit 1
fi
if ! timeout 90 "$GODOT_BIN" --headless --path "$STAGE" -- --verify-lua-runtime >"$STAGE/preflight-luau.log" 2>&1; then
  tail -n 50 "$STAGE/preflight-luau.log" >&2
  exit 1
fi
grep -q BOBUX_LUA_SMOKE_OK "$STAGE/preflight-luau.log"
cd "$STAGE/services/bobux_api"
npm ci --omit=dev
"$NODE_BIN" --check server.js
if ! "$NODE_BIN" --test ./*.test.mjs >"$STAGE/preflight-api.log" 2>&1; then
  tail -n 60 "$STAGE/preflight-api.log" >&2
  exit 1
fi
pm2 describe bobux >/dev/null
pm2 describe bobux-api >/dev/null
test -f /opt/bobux-api/.env
# Verify protected credentials exist without displaying their values.
set -a
. /opt/bobux-api/.env
set +a
test -n "${{BOBUX_SERVICE_KEY:-}}"
python3 "$TRANSACTION_HELPER" snapshot --archive /tmp/bobux-hotfix.tar.gz \
  --backup "$BACKUP" --server-root "$REMOTE_ROOT" --api-root /opt/bobux-api \
  --web-root "$WEB_ROOT" --versioned-windows "$VERSIONED_WINDOWS" --versioned-mobile "$VERSIONED_MOBILE"
RUNTIME_CHANGED=1
pm2 stop bobux bobux-api >/dev/null
python3 "$TRANSACTION_HELPER" retire-legacy --backup "$BACKUP"
mkdir -p "$REMOTE_ROOT" "$WEB_ROOT/launcher" "$WEB_ROOT/downloads" "$WEB_ROOT/mobile" /var/log/bobux
rsync -a --exclude='preflight-*.log' "$STAGE/" "$REMOTE_ROOT/"


if [ -f "$REMOTE_ROOT/ops/vps/admin.html" ]; then
  install -m 0644 "$REMOTE_ROOT/ops/vps/admin.html" "$WEB_ROOT/admin.html"
fi

test -f "$REMOTE_ROOT/ops/vps/bobux_nginx.conf"
install -m 0644 "$REMOTE_ROOT/ops/vps/bobux_nginx.conf" /etc/nginx/sites-available/bobux
test -e /etc/nginx/sites-enabled/bobux
nginx -t
systemctl reload nginx

test -d "$REMOTE_ROOT/services/bobux_api"
mkdir -p /opt/bobux-api
rsync -a --delete --exclude='.env*' --exclude=data --exclude=storage --exclude=uploads --exclude='*.sqlite*' --exclude='*.db*' "$REMOTE_ROOT/services/bobux_api/" /opt/bobux-api/
cd /opt/bobux-api
set -a
if [ -f /opt/bobux-api/.env ]; then
  . /opt/bobux-api/.env
fi
set +a
pm2 restart bobux-api bobux --update-env

# PM2 reports the process online before its API initialization has completed.
# Wait for actual readiness, retaining rollback on a bounded startup failure.
API_READY=0
for attempt in {{1..60}}; do
  if curl -fsS --connect-timeout 1 --max-time 2 http://127.0.0.1:3000/api/health 2>/dev/null | grep -q '"ok":true'; then
    API_READY=1
    break
  fi
  sleep 1
done
test "$API_READY" = 1
echo 'API readiness check passed'
python3 - <<'PY'
import socket, time
for attempt in range(30):
    try:
        with socket.create_connection(('127.0.0.1', 9000), timeout=1):
            break
    except OSError:
        if attempt == 29:
            raise
        time.sleep(1)
print('Dedicated WebSocket server is listening')
PY

# Publish large artifacts first. Manifests are switched only after every hash matches.
install -m 0644 "/tmp/$VERSIONED_WINDOWS" "$WEB_ROOT/downloads/Bobux-Windows.zip.new"
install -m 0644 "/tmp/$VERSIONED_WINDOWS" "$WEB_ROOT/downloads/$VERSIONED_WINDOWS.new"
install -m 0644 /tmp/BobuxLauncher-Windows.zip "$WEB_ROOT/downloads/BobuxLauncher-Windows.zip.new"
install -m 0644 "/tmp/$VERSIONED_MOBILE" "$WEB_ROOT/mobile/Bobux-Android.apk.new"
install -m 0644 "/tmp/$VERSIONED_MOBILE" "$WEB_ROOT/mobile/$VERSIONED_MOBILE.new"

echo "{hashes['windows']}  $WEB_ROOT/downloads/Bobux-Windows.zip.new" | sha256sum -c -
echo "{hashes['windows']}  $WEB_ROOT/downloads/$VERSIONED_WINDOWS.new" | sha256sum -c -
echo "{hashes['launcher']}  $WEB_ROOT/downloads/BobuxLauncher-Windows.zip.new" | sha256sum -c -
echo "{hashes['mobile']}  $WEB_ROOT/mobile/Bobux-Android.apk.new" | sha256sum -c -
echo "{hashes['mobile']}  $WEB_ROOT/mobile/$VERSIONED_MOBILE.new" | sha256sum -c -

mv -f "$WEB_ROOT/downloads/Bobux-Windows.zip.new" "$WEB_ROOT/downloads/Bobux-Windows.zip"
mv -f "$WEB_ROOT/downloads/$VERSIONED_WINDOWS.new" "$WEB_ROOT/downloads/$VERSIONED_WINDOWS"
mv -f "$WEB_ROOT/downloads/BobuxLauncher-Windows.zip.new" "$WEB_ROOT/downloads/BobuxLauncher-Windows.zip"
mv -f "$WEB_ROOT/mobile/Bobux-Android.apk.new" "$WEB_ROOT/mobile/Bobux-Android.apk"
mv -f "$WEB_ROOT/mobile/$VERSIONED_MOBILE.new" "$WEB_ROOT/mobile/$VERSIONED_MOBILE"

for artifact in BobuxSetup.exe Bobux-x86_64.AppImage desktop-latest.json; do
  install -m 0644 "/tmp/$artifact" "$WEB_ROOT/downloads/$artifact.new"
  cmp "/tmp/$artifact" "$WEB_ROOT/downloads/$artifact.new"
  mv -f "$WEB_ROOT/downloads/$artifact.new" "$WEB_ROOT/downloads/$artifact"
done
mkdir -p "$WEB_ROOT/assets"
cp -a "$REMOTE_ROOT/ops/vps/assets/." "$WEB_ROOT/assets/"
install -m 0644 "$REMOTE_ROOT/ops/vps/index.html" "$WEB_ROOT/index.html.new"
mv -f "$WEB_ROOT/index.html.new" "$WEB_ROOT/index.html"

install -m 0644 /tmp/latest.json "$WEB_ROOT/launcher/latest.json.new"
install -m 0644 /tmp/latest.json "$WEB_ROOT/downloads/latest.json.new"
install -m 0644 /tmp/mobile-latest.json "$WEB_ROOT/mobile/latest.json.new"
mv -f "$WEB_ROOT/launcher/latest.json.new" "$WEB_ROOT/launcher/latest.json"
mv -f "$WEB_ROOT/downloads/latest.json.new" "$WEB_ROOT/downloads/latest.json"
mv -f "$WEB_ROOT/mobile/latest.json.new" "$WEB_ROOT/mobile/latest.json"

curl -fsS http://127.0.0.1/launcher/latest.json | grep -q '"build":[[:space:]]*{build}'
curl -fsS http://127.0.0.1/mobile/latest.json | grep -q '"build":[[:space:]]*{mobile_build}'
curl -fsS http://127.0.0.1/api/health | grep -q '"ok":true'
pm2 save
RUNTIME_CHANGED=0
trap - ERR
echo "=== DEPLOY COMPLETE ==="
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="109.71.245.162")
    parser.add_argument("--port", type=int, default=22)
    parser.add_argument("--user", default="root")
    parser.add_argument("--version", default="0.1.34")
    parser.add_argument("--build", type=int, default=39)
    parser.add_argument("--mobile-version", default="0.1.26-mobile")
    parser.add_argument("--mobile-build", type=int, default=27)
    parser.add_argument("--remote-root", default="/opt/bobux-server")
    parser.add_argument("--web-root", default="/var/www/bobux")
    parser.add_argument("--key-file", default=os.environ.get("BOBUX_DEPLOY_KEY_FILE", ""))
    parser.add_argument(
        "--known-hosts",
        default=os.environ.get(
            "BOBUX_DEPLOY_KNOWN_HOSTS",
            str(Path.home() / ".ssh" / "known_hosts"),
        ),
    )
    parser.add_argument("--skip-upload", action="store_true")
    parser.add_argument("--allow-redeploy", action="store_true", help="Explicit recovery only: permit replacing the same live build.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if re.fullmatch(r"\d+\.\d+\.\d+", args.version) is None or re.fullmatch(r"\d+\.\d+\.\d+-mobile", args.mobile_version) is None:
        raise RuntimeError("Release versions must use MAJOR.MINOR.PATCH and MAJOR.MINOR.PATCH-mobile.")
    if args.build < 1 or args.mobile_build < 1:
        raise RuntimeError("Release build numbers must be positive.")
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(errors="backslashreplace")
    password = os.environ.get("BOBUX_DEPLOY_PASSWORD", "")
    key_file = Path(args.key_file).expanduser() if args.key_file else None
    if key_file is not None and not key_file.is_file():
        raise RuntimeError(f"SSH private key does not exist: {key_file}")
    if key_file is None and not password:
        raise RuntimeError(
            "Set --key-file/BOBUX_DEPLOY_KEY_FILE or BOBUX_DEPLOY_PASSWORD."
        )
    known_hosts = Path(args.known_hosts).expanduser()
    if not known_hosts.is_file():
        raise RuntimeError(f"Pinned SSH known_hosts file does not exist: {known_hosts}")

    project_root = Path(__file__).resolve().parent.parent
    files = {
        "/tmp/bobux-hotfix.tar.gz": project_root
        / "dist"
        / f"bobux-hotfix-build{args.build}.tar.gz",
        "/tmp/latest.json": project_root / "game" / "launcher" / "latest.json",
        f"/tmp/Bobux-Windows-{args.version}-build{args.build}.zip": project_root
        / "dist"
        / "release"
        / f"Bobux-Windows-{args.version}-build{args.build}.zip",
        "/tmp/BobuxLauncher-Windows.zip": project_root
        / "dist"
        / "BobuxLauncher-Windows.zip",
        "/tmp/mobile-latest.json": project_root / "mobile" / "latest.json",
        f"/tmp/Bobux-Android-{args.mobile_version}-build{args.mobile_build}.apk": project_root
        / "dist"
        / "release"
        / f"Bobux-Android-{args.mobile_version}-build{args.mobile_build}.apk",
    }
    for name in ("BobuxSetup.exe", "Bobux-Linux-x86_64.tar.gz", "desktop-latest.json"):
        files["/tmp/" + name] = project_root / "dist" / "release" / name
    for remote_path, local_path in files.items():
        minimum = 256 if local_path.suffix == ".json" else 1024 * 1024
        require_file(local_path, minimum)
    from validate_server_release_archive import validate_archive
    validate_archive(files["/tmp/bobux-hotfix.tar.gz"])
    from validate_native_release_artifacts import validate_native_archive
    validate_native_archive("server", files["/tmp/bobux-hotfix.tar.gz"], project_root)
    windows_package = files[f"/tmp/Bobux-Windows-{args.version}-build{args.build}.zip"]
    with zipfile.ZipFile(windows_package) as package:
        windows_marker = json.loads(package.read("version.json"))
    windows_architecture = windows_marker.get("arch")
    if windows_architecture not in {"x86_32", "x86_64"}:
        raise RuntimeError("Windows package is missing its native architecture marker.")
    validate_native_archive("windows", windows_package, project_root, windows_architecture)
    validate_native_archive("apk", files[f"/tmp/Bobux-Android-{args.mobile_version}-build{args.mobile_build}.apk"], project_root)
    validate_native_archive("linux", files["/tmp/Bobux-Linux-x86_64.tar.gz"], project_root)

    launcher_manifest = json.loads(files["/tmp/latest.json"].read_text("utf-8"))
    mobile_manifest = json.loads(files["/tmp/mobile-latest.json"].read_text("utf-8"))
    hashes = {
        "hotfix": sha256_file(files["/tmp/bobux-hotfix.tar.gz"]),
        "windows": sha256_file(
            files[f"/tmp/Bobux-Windows-{args.version}-build{args.build}.zip"]
        ),
        "launcher": sha256_file(files["/tmp/BobuxLauncher-Windows.zip"]),
        "mobile": sha256_file(
            files[
                f"/tmp/Bobux-Android-{args.mobile_version}-build{args.mobile_build}.apk"
            ]
        ),
    }
    for key, name in (("setup", "BobuxSetup.exe"), ("linux", "Bobux-Linux-x86_64.tar.gz"), ("desktop", "desktop-latest.json")):
        hashes[key] = sha256_file(files["/tmp/" + name])
    desktop = json.loads(files["/tmp/desktop-latest.json"].read_text("utf-8"))
    if desktop["version"] != args.version or desktop["build"] != args.build:
        raise RuntimeError("Desktop manifest version mismatch")
    for platform, key in (("windows", "setup"), ("linux", "linux")):
        if desktop["platforms"][platform]["sha256"].upper() != hashes[key]:
            raise RuntimeError("Desktop package hash mismatch")
    if hashes["windows"] != str(launcher_manifest["sha256"]).upper():
        raise RuntimeError("Windows manifest SHA256 does not match the release ZIP.")
    if hashes["launcher"] != str(launcher_manifest["launcher"]["sha256"]).upper():
        raise RuntimeError("Launcher manifest SHA256 does not match the launcher ZIP.")
    if hashes["mobile"] != str(mobile_manifest["android"]["sha256"]).upper():
        raise RuntimeError("Mobile manifest SHA256 does not match the APK.")
    if int(launcher_manifest.get("build", -1)) != args.build:
        raise RuntimeError("Windows manifest build does not match --build.")
    if str(launcher_manifest.get("version", "")) != args.version:
        raise RuntimeError("Windows manifest version does not match --version.")
    if int(mobile_manifest.get("build", -1)) != args.mobile_build:
        raise RuntimeError("Mobile manifest build does not match --mobile-build.")
    if str(mobile_manifest.get("version", "")) != args.mobile_version:
        raise RuntimeError("Mobile manifest version does not match --mobile-version.")

    client = paramiko.SSHClient()
    client.load_host_keys(str(known_hosts))
    client.set_missing_host_key_policy(paramiko.RejectPolicy())
    print(f"Connecting to {args.user}@{args.host}:{args.port}...", flush=True)
    client.connect(
        args.host,
        port=args.port,
        username=args.user,
        password=password or None,
        key_filename=str(key_file) if key_file is not None else None,
        allow_agent=False,
        look_for_keys=False,
        timeout=20,
        banner_timeout=20,
        auth_timeout=20,
    )
    try:
        run_remote(client, "df -h /tmp /opt /var/www | tail -n +2")
        sftp = client.open_sftp()
        try:
            with sftp.open(posixpath.join(args.web_root, "launcher/latest.json"), "r") as remote_manifest:
                current_windows = json.loads(remote_manifest.read().decode("utf-8"))
            with sftp.open(posixpath.join(args.web_root, "mobile/latest.json"), "r") as remote_manifest:
                current_mobile = json.loads(remote_manifest.read().decode("utf-8"))
            if not args.allow_redeploy and (
                args.build <= int(current_windows["build"]) or args.mobile_build <= int(current_mobile["build"])
            ):
                raise RuntimeError("Production PC and Android builds must be newer than the live manifests; use --allow-redeploy only for explicit recovery.")
            if args.build < int(current_windows["build"]) or args.mobile_build < int(current_mobile["build"]):
                raise RuntimeError("Deployment refuses to downgrade production builds.")
            if not args.skip_upload:
                for remote_path, local_path in files.items():
                    print(f"Uploading {local_path.name} -> {remote_path}", flush=True)
                    upload_atomic(sftp, local_path, remote_path)
            else:
                print("Reusing previously uploaded /tmp artifacts.", flush=True)
            script = build_remote_script(
                version=args.version,
                build=args.build,
                mobile_version=args.mobile_version,
                mobile_build=args.mobile_build,
                remote_root=args.remote_root,
                web_root=args.web_root,
                hashes=hashes,
            )
            script_path = "/tmp/bobux-release-deploy.sh"
            with sftp.open(script_path, "w") as remote_script:
                remote_script.write(script.encode("utf-8"))
            sftp.chmod(script_path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
        finally:
            sftp.close()
        run_remote(client, "bash /tmp/bobux-release-deploy.sh", timeout=1200)
        sftp = client.open_sftp()
        try:
            for name in ("Bobux-x86_64.AppImage", "desktop-latest.json"):
                sftp.get("/tmp/" + name, str(Path("dist/release") / name))
            ai_environment_updated = sync_remote_ai_environment(sftp)
        finally:
            sftp.close()
        if ai_environment_updated:
            print("Updated protected Bobux AI server configuration.", flush=True)
            run_remote(
                client,
                "cd /opt/bobux-api && set -a && . ./.env && set +a && "
                "pm2 restart bobux-api --update-env >/dev/null && "
                "echo 'OK: Bobux AI configuration activated'",
            )
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
