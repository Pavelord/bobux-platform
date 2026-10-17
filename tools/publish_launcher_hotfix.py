#!/usr/bin/env python3
"""Publish a verified launcher/installer without replacing the running game/API."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import time
import zipfile

import paramiko

from deploy_bobux_release_paramiko import upload_atomic, run_remote


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(sftp, path: str) -> dict:
    with sftp.open(path, "r") as source:
        return json.loads(source.read().decode("utf-8-sig"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--launcher-version", required=True)
    parser.add_argument("--launcher-build", required=True, type=int)
    parser.add_argument("--game-version", required=True)
    parser.add_argument("--game-build", required=True, type=int)
    parser.add_argument("--key-file", required=True)
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--host", default="109.71.245.162")
    args = parser.parse_args()
    if (not re.fullmatch(r"\d+\.\d+\.\d+", args.launcher_version) or args.launcher_build < 1
            or not re.fullmatch(r"\d+\.\d+\.\d+", args.game_version) or args.game_build < 1):
        raise ValueError("Invalid launcher release version/build")
    root = Path(__file__).resolve().parent.parent
    archive = root / "dist/BobuxLauncher-Windows.zip"
    setup = root / "dist/release/BobuxSetup.exe"
    if archive.stat().st_size < 1_000_000 or setup.stat().st_size < 1_000_000:
        raise ValueError("Missing launcher or installer")
    with zipfile.ZipFile(archive) as package:
        if package.testzip() is not None:
            raise ValueError("Launcher archive CRC failed")
        marker = json.loads(package.read("version.json"))
        if (marker.get("version"), marker.get("build")) != (args.launcher_version, args.launcher_build):
            raise ValueError("Launcher marker does not match requested release")
        if package.getinfo("BobuxLauncher.exe").file_size < 10_000_000:
            raise ValueError("Launcher executable is undersized")
    client = paramiko.SSHClient()
    client.load_host_keys(args.known_hosts)
    client.set_missing_host_key_policy(paramiko.RejectPolicy())
    client.connect(args.host, username="root", key_filename=args.key_file,
                   allow_agent=False, look_for_keys=False, timeout=20)
    release = root / "dist/release"
    stage = f"/tmp/bobux-launcher-hotfix-{args.launcher_build}-{int(time.time())}"
    web = "/var/www/bobux"
    versioned_name = f"BobuxLauncher-Windows-{args.launcher_version}-build{args.launcher_build}.zip"
    base = f"http://{args.host}"
    try:
        with client.open_sftp() as sftp:
            game = read_json(sftp, web + "/launcher/latest.json")
            alias = read_json(sftp, web + "/downloads/latest.json")
            desktop = read_json(sftp, web + "/downloads/desktop-latest.json")
            if game != alias:
                raise ValueError("Live game manifest aliases disagree")
            if (game.get("version"), game.get("build")) != (args.game_version, args.game_build):
                raise ValueError("Live game changed; refuse a stale launcher publication")
            if (desktop.get("version"), desktop.get("build")) != (args.game_version, args.game_build):
                raise ValueError("Live desktop manifest does not match the game")
            if args.launcher_build <= int(game.get("launcher", {}).get("build", 0)):
                raise ValueError("Launcher builds must increase")
            previous_game_digest = hashlib.sha256(json.dumps(game, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()
            previous_desktop_digest = hashlib.sha256(json.dumps(desktop, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()
            game["launcher"] = {
                "version": args.launcher_version,
                "build": args.launcher_build,
                "sha256": digest(archive).upper(),
                "package_size": archive.stat().st_size,
                "zip_url": base + "/downloads/" + versioned_name,
                "mirrors": [base + "/downloads/" + versioned_name, base + "/downloads/BobuxLauncher-Windows.zip"],
            }
            desktop["platforms"]["windows"]["sha256"] = digest(setup)
            desktop["platforms"]["windows"]["size"] = setup.stat().st_size
            new_game = release / f"launcher-hotfix-{args.launcher_build}-latest.json"
            new_desktop = release / f"launcher-hotfix-{args.launcher_build}-desktop.json"
            new_game.write_text(json.dumps(game, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            new_desktop.write_text(json.dumps(desktop, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            sftp.mkdir(stage, mode=0o700)
            for local, name in [(archive, "launcher.zip"), (setup, "setup.exe"),
                                (new_game, "latest.json"), (new_desktop, "desktop.json")]:
                upload_atomic(sftp, local, stage + "/" + name)
        q = shlex.quote
        checks = "\n".join(
            f"echo {q(digest(local) + '  ' + stage + '/' + name)} | sha256sum -c -"
            for local, name in [(archive, "launcher.zip"), (setup, "setup.exe"),
                                (new_game, "latest.json"), (new_desktop, "desktop.json")]
        )
        script = f"""set -Eeuo pipefail
STAGE={q(stage)}
WEB={q(web)}
BACKUP=/opt/bobux-launcher-rollback-{args.launcher_build}-$(date -u +%Y%m%dT%H%M%SZ)
{checks}
python3 - <<'PY'
import hashlib, json
from pathlib import Path
def current_digest(path):
    value = json.loads(Path(path).read_text())
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode('utf-8')).hexdigest()
assert current_digest('{web}/launcher/latest.json') == '{previous_game_digest}', 'Live game manifest changed during upload'
assert current_digest('{web}/downloads/latest.json') == '{previous_game_digest}', 'Live game alias changed during upload'
assert current_digest('{web}/downloads/desktop-latest.json') == '{previous_desktop_digest}', 'Live desktop manifest changed during upload'
PY
mkdir -m 0700 "$BACKUP"
for relative in downloads/BobuxLauncher-Windows.zip downloads/BobuxSetup.exe launcher/latest.json downloads/latest.json downloads/desktop-latest.json; do
  mkdir -p "$BACKUP/$(dirname "$relative")"
  cp -p "$WEB/$relative" "$BACKUP/$relative"
done
rollback() {{
  status=$?
  trap - ERR
  for relative in downloads/BobuxLauncher-Windows.zip downloads/BobuxSetup.exe launcher/latest.json downloads/latest.json downloads/desktop-latest.json; do
    install -m 0644 "$BACKUP/$relative" "$WEB/$relative.restore"
    mv -f "$WEB/$relative.restore" "$WEB/$relative"
  done
  echo 'Launcher publication rolled back.' >&2
  exit "$status"
}}
trap rollback ERR
install -m 0644 "$STAGE/launcher.zip" "$WEB/downloads/{versioned_name}.new"
mv -f "$WEB/downloads/{versioned_name}.new" "$WEB/downloads/{versioned_name}"
install -m 0644 "$STAGE/launcher.zip" "$WEB/downloads/BobuxLauncher-Windows.zip.new"
mv -f "$WEB/downloads/BobuxLauncher-Windows.zip.new" "$WEB/downloads/BobuxLauncher-Windows.zip"
install -m 0644 "$STAGE/setup.exe" "$WEB/downloads/BobuxSetup.exe.new"
mv -f "$WEB/downloads/BobuxSetup.exe.new" "$WEB/downloads/BobuxSetup.exe"
for target in launcher/latest.json downloads/latest.json; do
  install -m 0644 "$STAGE/latest.json" "$WEB/$target.new"
  mv -f "$WEB/$target.new" "$WEB/$target"
done
install -m 0644 "$STAGE/desktop.json" "$WEB/downloads/desktop-latest.json.new"
mv -f "$WEB/downloads/desktop-latest.json.new" "$WEB/downloads/desktop-latest.json"
curl -fsS http://127.0.0.1/api/health | grep -q '"ok":true'
python3 - <<'PY'
import json
from pathlib import Path
base = Path('{web}')
game = json.loads((base / 'launcher/latest.json').read_text())
assert game == json.loads((base / 'downloads/latest.json').read_text())
assert (game['build'], game['version']) == ({args.game_build}, '{args.game_version}')
assert (game['launcher']['build'], game['launcher']['version']) == ({args.launcher_build}, '{args.launcher_version}')
print('LAUNCHER_HOTFIX_PUBLISHED')
PY
trap - ERR
"""
        with client.open_sftp() as sftp:
            remote_script = stage + "/publish.sh"
            with sftp.open(remote_script, "w") as destination:
                destination.write(script.encode("utf-8"))
        run_remote(client, "bash " + q(remote_script), timeout=180)
        (root / "game/launcher/latest.json").write_text(new_game.read_text(encoding="utf-8"), encoding="utf-8")
        (release / "desktop-latest.json").write_text(new_desktop.read_text(encoding="utf-8"), encoding="utf-8")
        print("Game, Android, API and active rooms were not restarted.")
    finally:
        client.close()


if __name__ == "__main__":
    main()
