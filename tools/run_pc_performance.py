"""Benchmark the exported Windows client against an isolated local server.

This uses the shipped login entry point's opt-in --performance-probe, rather
than an editor/debug executable or a command-line scene replacement. Accounts
and the live room registry are never used. Public map/media reads may occur
when an optional cached asset is missing.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import struct
import subprocess
import sys
import time
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
MAPS = {
    "park": "akx0oto939gi501_bobux_park_krut",
    "valley": "akx0oto939gi501_dolina_semi_vetrov",
    "nds": "z9ovqynlv860sgw_narural disaster survival - bobux edition",
    "lift": "evd29np4936q499_normalnyi_lift",
    "city_rp": "evd29np4936q499_бобукс сити рп",
}
USERDATA = Path("Godot/app_userdata/Bobux")


def isolated_path(value: Path) -> Path:
    path = value.resolve()
    if not path.is_relative_to((ROOT / ".codex-tmp").resolve()):
        raise ValueError("Benchmark userdata/output must stay under .codex-tmp")
    return path


def guest_environment(appdata: Path, port: int) -> dict[str, str]:
    # Clearing the server key alone is insufficient: inherited bearer, test
    # identity and a saved refresh token could otherwise reach the live API.
    env = {
        key: value for key, value in os.environ.items()
        if not key.upper().startswith(("BOBUX_", "ROBLOXCLONE_", "CODEX_TEST_", "DEDICATED_PROBE_"))
        and key.upper() not in {"GODOT_SERVER_PORT", "GODOT_SERVER_MAP", "PUBLIC_SERVER_WS_URL"}
    }
    env["APPDATA"] = str(isolated_path(appdata))
    env["GODOT_SERVER_PORT"] = str(port)
    env["PUBLIC_SERVER_WS_URL"] = f"ws://127.0.0.1:{port}"
    return env


def assert_guest_userdata(appdata: Path) -> None:
    userdata = isolated_path(appdata) / USERDATA
    if any(userdata.glob("**/*auth_session.json")):
        raise ValueError("Benchmark APPDATA contains an authentication session; choose a fresh directory")
    profile = userdata / "session/current_profile.json"
    if profile.exists() and json.loads(profile.read_text(encoding="utf-8")).get("user_id"):
        raise ValueError("Benchmark APPDATA contains an account profile; choose a fresh directory")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def executable_identity(executable: Path, version_file: Path | None) -> dict:
    with executable.open("rb") as stream:
        if stream.read(2) != b"MZ":
            raise ValueError("The client is not a Windows PE executable")
        stream.seek(0x3C)
        header = struct.unpack("<I", stream.read(4))[0]
        stream.seek(header)
        if stream.read(4) != b"PE\0\0":
            raise ValueError("Invalid client PE header")
        machine = struct.unpack("<H", stream.read(2))[0]
    if machine != 0x14C:
        raise ValueError("The shipping performance run requires the x86_32 client")
    identity = {"path": str(executable), "bytes": executable.stat().st_size,
                "sha256": sha256(executable), "arch": "x86_32"}
    if version_file is not None:
        version = json.loads(version_file.read_text(encoding="utf-8"))
        if (str(version.get("executable_sha256", "")).lower() != identity["sha256"]
                or version.get("executable_size") != identity["bytes"]
                or version.get("arch") != "x86_32"):
            raise ValueError("Client does not match the packaged release version.json")
        identity.update({"version": version["version"], "build": version["build"],
                         "version_file": str(version_file)})
    return identity


def seed_city_cache(server_appdata: Path) -> None:
    target = server_appdata / USERDATA / "cache/maps" / MAPS["city_rp"]
    if (target / "map_data.json").exists() and (target / "meta.json").exists():
        return
    source = ROOT / ".codex-tmp/halloween/city-rp/city-map.json"
    audit_path = source.with_name("audit.json")
    if not source.exists() or not audit_path.exists():
        raise ValueError("City RP original-map audit/cache is missing")
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    if audit["metadata"]["id"] != MAPS["city_rp"] or sha256(source) != audit["map_sha256"]:
        raise ValueError("City RP source does not match its published-map audit")
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target / "map_data.json")
    metadata = {"name": audit["metadata"]["name"], "cloud_map_id": MAPS["city_rp"],
                "cloud_version_id": "", "creator": "Cloud", "description": "", "thumbnail": ""}
    (target / "meta.json").write_text(json.dumps(metadata, ensure_ascii=False), encoding="utf-8")
    (target / "version.txt").write_text("", encoding="utf-8")


def prepare_cache(server_appdata: Path, client_appdata: Path, selected: list[str], warm: bool) -> dict:
    if "city_rp" in selected:
        seed_city_cache(server_appdata)
    source = server_appdata / USERDATA / "cache/maps"
    hashes = {}
    for key in selected:
        folder = source / MAPS[key]
        if not (folder / "map_data.json").exists() or not (folder / "meta.json").exists():
            raise ValueError(f"Original server map cache missing: {key}")
        hashes[key] = sha256(folder / "map_data.json")
        if warm:
            destination = client_appdata / USERDATA / "cache/maps" / MAPS[key]
            shutil.copytree(folder, destination, dirs_exist_ok=True)
    return {"mode": "warm" if warm else "cold_client", "map_file_sha256": hashes,
            "copied_only": "cache/maps; no session/profile files"}


def wait_server(process: subprocess.Popen, log: Path, port: int, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    marker = f"WebSocket authoritative server is live on port {port}."
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"Private server exited with {process.returncode}; see {log}")
        if marker in log.read_text(encoding="utf-8", errors="replace"):
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                return
        time.sleep(0.2)
    raise TimeoutError(f"Private server did not become ready within {timeout:g}s; see {log}")


def stop_owned(process: subprocess.Popen | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=10)


def client_log_source(file_log: Path, console_log: Path) -> Path:
    # The shipping engine can disable its FileLogger while --log-file still
    # creates an empty path. Its stdout remains captured by the runner.
    return file_log if file_log.exists() and file_log.stat().st_size else console_log


def public_server_url(value: str) -> str:
    parsed = urlparse(value)
    if (parsed.scheme not in {"ws", "wss"} or not parsed.hostname
            or parsed.username is not None or parsed.password is not None
            or parsed.query or parsed.fragment):
        raise ValueError("--server requires a ws/wss URL without credentials, query or fragment")
    return value


def validate_report(report: dict, selected: list[str], runs: int, tag: str, exit_code: int,
                    platform: str = "Windows") -> None:
    if exit_code != 0 or report.get("tag") != tag or report.get("platform") != platform or report.get("failures"):
        raise RuntimeError("Shipping client benchmark failed; inspect the retained report/log")
    expected = {(key, iteration) for key in selected for iteration in range(runs)}
    records = report.get("results", [])
    actual = {(row.get("map"), row.get("run")) for row in records}
    if actual != expected or len(records) != len(expected):
        raise RuntimeError("Shipping client report is incomplete or contains duplicate runs")
    for record in records:
        if record.get("runtime", {}).get("failed", 0) or record.get("frame", {}).get("frames", 0) <= 0:
            raise RuntimeError(f"Client runtime/sample failed for {record.get('map')}")
        if record["map"] in {"park", "valley"} and not record.get("touch_start"):
            raise RuntimeError(f"Published start button did not respond in {record['map']}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=ROOT / "dist/game/Bobux.exe")
    parser.add_argument("--godot", type=Path, default=ROOT / ".codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe")
    parser.add_argument("--version-file", type=Path, help="Required for a run: packaged stage/version.json for executable checksum verification")
    parser.add_argument("--tag", default="release55")
    parser.add_argument("--maps", default=",".join(MAPS))
    parser.add_argument("--seconds", type=int, default=15)
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--port", type=int, default=17861)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--server-appdata", type=Path, default=ROOT / ".codex-tmp/performance-server")
    parser.add_argument("--client-appdata", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--cold-client", action="store_true", help="Skip copying warm map caches into a fresh client directory")
    parser.add_argument("--rotate-camera", action="store_true")
    parser.add_argument("--server", help="Optional published ws/wss server; no local server process is created")
    parser.add_argument("--prepare-only", action="store_true", help="Validate isolated paths/cache without launching the GPU benchmark")
    args = parser.parse_args()
    remote_server = public_server_url(args.server) if args.server else None
    selected = args.maps.split(",")
    if not selected or len(set(selected)) != len(selected) or any(key not in MAPS for key in selected):
        parser.error("--maps must contain unique known map names")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.tag):
        parser.error("--tag accepts only ASCII letters, numbers, '-' and '_'")
    if not 5 <= args.seconds <= 180 or not 1 <= args.runs <= 5 or not 1024 <= args.port <= 65535 or args.timeout < 30:
        parser.error("Invalid seconds/runs/port/timeout range")
    server_appdata = isolated_path(args.server_appdata)
    client_appdata = isolated_path(args.client_appdata or ROOT / f".codex-tmp/{args.tag}-pc")
    output = isolated_path(args.output or ROOT / f".codex-tmp/performance/pc-{args.tag}.json")
    if server_appdata == client_appdata:
        parser.error("Server/client APPDATA must be separate")
    for appdata in (server_appdata, client_appdata):
        assert_guest_userdata(appdata)
        appdata.mkdir(parents=True, exist_ok=True)
    if args.cold_client and (client_appdata / USERDATA / "cache/maps").exists():
        parser.error("--cold-client requires a fresh client APPDATA without map caches")
    cache = prepare_cache(server_appdata, client_appdata, selected, not args.cold_client)
    output.parent.mkdir(parents=True, exist_ok=True)
    if args.prepare_only:
        print(json.dumps({"prepared": True, "server_appdata": str(server_appdata),
                          "client_appdata": str(client_appdata), "cache": cache}, ensure_ascii=False, indent=2))
        return 0
    if args.version_file is None:
        parser.error("--version-file is required to verify the actual shipping executable")
    executable = args.exe.resolve()
    identity = executable_identity(executable, args.version_file.resolve() if args.version_file else None)
    if remote_server is None:
        try:
            with socket.create_connection(("127.0.0.1", args.port), timeout=0.5):
                raise RuntimeError("Private benchmark port is already occupied; no existing process will be stopped")
        except (ConnectionRefusedError, TimeoutError, OSError):
            pass
    source_report = client_appdata / USERDATA / "performance" / f"{args.tag}.json"
    source_report.unlink(missing_ok=True)
    server_log = output.with_suffix(".server.log")
    client_log = output.with_suffix(".client.log")
    client_console_log = output.with_suffix(".client-console.log")
    client_log.unlink(missing_ok=True)
    server = client = None
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    started = time.monotonic()
    print(f"[pc] Shipping {identity['arch']} client sha256={identity['sha256']} maps={','.join(selected)}", flush=True)
    report = {}
    try:
        with server_log.open("w", encoding="utf-8") as server_stream, client_console_log.open("w", encoding="utf-8") as client_stream:
            if remote_server is None:
                server = subprocess.Popen([str(args.godot.resolve()), "--headless", "--path", str(ROOT),
                                           "--script", "server/server_main.gd"], cwd=ROOT,
                                          env=guest_environment(server_appdata, args.port), stdout=server_stream,
                                          stderr=subprocess.STDOUT, creationflags=flags)
                wait_server(server, server_log, args.port, min(60, args.timeout))
            server_url = remote_server or f"ws://127.0.0.1:{args.port}"
            command = [str(executable), "--log-file", str(client_log), "--", "--performance-probe",
                       f"--maps={','.join(selected)}", f"--seconds={args.seconds}", f"--runs={args.runs}",
                       f"--server={server_url}", f"--tag={args.tag}"]
            if args.rotate_camera:
                command.append("--rotate-camera")
            client = subprocess.Popen(command, cwd=executable.parent,
                                      env=guest_environment(client_appdata, args.port), stdout=client_stream,
                                      stderr=subprocess.STDOUT, creationflags=flags)
            delivered = set()
            deadline = time.monotonic() + args.timeout
            while client.poll() is None:
                if server is not None and server.poll() is not None:
                    raise RuntimeError("Private authoritative server exited during the client run")
                if time.monotonic() > deadline:
                    raise TimeoutError(f"Shipping benchmark exceeded {args.timeout}s; see {client_log}")
                current_log = client_log_source(client_log, client_console_log)
                if current_log.exists():
                    for line in current_log.read_text(encoding="utf-8", errors="replace").splitlines():
                        if "[perf] RESULT " in line and line not in delivered:
                            delivered.add(line)
                            row = json.loads(line.split("[perf] RESULT ", 1)[1])
                            print(f"[pc] {row['map']} run={row['run']} join_ms={row['join_ms']} "
                                  f"fps={row['frame']['fps']:.2f} p95_ms={row['frame']['p95_ms']:.3f} "
                                  f"failed={row['runtime']['failed']}", flush=True)
                time.sleep(1)
            if not source_report.exists():
                raise RuntimeError(f"Shipping client did not write its benchmark report; see {client_log}")
            report = json.loads(source_report.read_text(encoding="utf-8"))
            report["shipping_client"] = identity
            if remote_server:
                report["public_server"] = {"url": server_url, "account": "isolated guest",
                                           "server_diagnostics": "not collected locally"}
            else:
                report["private_server"] = {"url": server_url, "live_registry_enabled": False}
            report["cache"] = cache
            report["wall_seconds"] = round(time.monotonic() - started, 3)
            report["client_exit_code"] = client.returncode
            actual_log = client_log_source(client_log, client_console_log)
            report["client_log_source"] = str(actual_log)
            log_text = actual_log.read_text(encoding="utf-8", errors="replace")
            errors = [line for line in log_text.splitlines()
                      if "SCRIPT ERROR:" in line or line.startswith("ERROR:")]
            report["client_log_error_count"] = len(errors)
            report["client_log_errors"] = errors[:20]
            server_errors = [line for line in server_log.read_text(encoding="utf-8", errors="replace").splitlines()
                             if "SCRIPT ERROR:" in line or line.startswith("ERROR:")]
            report["server_log_error_count"] = len(server_errors)
            report["server_log_errors"] = server_errors[:20]
            for line in log_text.splitlines():
                if "[perf] BEGIN " in line:
                    report["device"] = json.loads(line.split("[perf] BEGIN ", 1)[1])
                    break
            output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
            validate_report(report, selected, args.runs, args.tag, client.returncode)
            if errors:
                raise RuntimeError(f"Shipping client logged {len(errors)} runtime/resource errors; see {client_log}")
            if server_errors:
                raise RuntimeError(f"Authoritative server logged {len(server_errors)} runtime/resource errors; see {server_log}")
            print(f"[pc] PASS {len(report['results'])} shipping-client map runs; {output}", flush=True)
            return 0
    finally:
        stop_owned(client)
        stop_owned(server)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, TimeoutError, OSError, json.JSONDecodeError) as error:
        print(f"[pc] FAIL: {error}", file=sys.stderr, flush=True)
        raise SystemExit(1)
