#!/usr/bin/env python3
"""Read-only audit of published Bobux artifacts, manifests and server processes.

Requires pinned SSH host keys. Never prints PM2 environment or raw server logs.
Only the local JSON report is written; no deployment or server mutation occurs.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import hashlib
import inspect
import json
import re
from pathlib import Path
import urllib.request


def parse_pm2_json(text: str) -> list[dict]:
    """PM2 may print a banner before jlist; only accept its process array."""
    decoder = json.JSONDecoder()
    for match in re.finditer(r"\[", text):
        try:
            value, _ = decoder.raw_decode(text, match.start())
        except json.JSONDecodeError:
            continue
        if isinstance(value, list) and all(isinstance(item, dict) and "name" in item and isinstance(item.get("pm2_env"), dict) for item in value):
            return value
    raise ValueError("PM2 process array is unavailable")


def process_summary(processes: list[dict]) -> list[dict]:
    """Explicit allowlist: never return environment, paths, arguments or logs."""
    output = []
    for item in processes:
        name = item.get("name")
        if name not in {"bobux", "bobux-api"}:
            continue
        env = item.get("pm2_env", {})
        status = env.get("status")
        output.append({
            "name": name,
            "status": status if status in {"online", "stopped", "stopping", "errored", "launching", "waiting restart", "one-launch-status"} else "unknown",
            "pid": item.get("pid") if isinstance(item.get("pid"), int) else None,
            "restart_count": env.get("restart_time") if isinstance(env.get("restart_time"), int) else None,
        })
    return output


def sha256_file(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def remote_audit_code(paths: list[str]) -> str:
    # Include the exact, tested sanitizers in the remote in-memory program.
    helpers = inspect.getsource(parse_pm2_json) + "\n" + inspect.getsource(process_summary)
    body = r'''
errors = []
def read_hash(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda: stream.read(1024*1024), b''):
            digest.update(data)
    return {'size': path.stat().st_size, 'sha256': digest.hexdigest()}
def capture(section, operation):
    try: return operation()
    except Exception as error:
        errors.append({'section': section, 'error_class': type(error).__name__})
        return None
def version(binary):
    output = subprocess.check_output([binary, '--version'], stderr=subprocess.DEVNULL, timeout=10).decode('utf-8', 'replace').strip()
    return output if re.fullmatch(r'[A-Za-z0-9_.+\-]{1,96}', output) else None
web = Path('/var/www/bobux')
server = Path('/opt/bobux-server')
artifacts = {path: capture('artifact:' + path, lambda path=path: read_hash(web / path.lstrip('/'))) for path in public_paths}
native = {}
for name in ['libbobuxluau.linux.template_debug.x86_64.so', 'libbobuxluau.linux.template_release.x86_64.so']:
    native[name] = capture('native:' + name, lambda name=name: read_hash(server / 'addons/luaAPI/bin' / name))
def protocol(relative):
    text = (server / relative).read_text(encoding='utf-8')
    match = re.search(r'const\s+NETWORK_PROTOCOL_VERSION\s*:\s*String\s*=\s*"([A-Za-z0-9_.\-]{1,128})"', text)
    return match.group(1) if match else None
protocols = {relative: capture('protocol:' + relative, lambda relative=relative: protocol(relative)) for relative in ['autoload/client_network.gd', 'server/server_main.gd']}
def project_version():
    text = (server / 'project.godot').read_text(encoding='utf-8')
    match = re.search(r'config/version="([0-9.]{1,32})"', text)
    return match.group(1) if match else None
def pm2_status():
    output = subprocess.check_output(['pm2', 'jlist'], stderr=subprocess.DEVNULL, timeout=25).decode('utf-8', 'replace')
    return process_summary(parse_pm2_json(output))
node = '/opt/bobux-runtime/node/bin/node'
if not Path(node).is_file(): node = shutil.which('node')
result = {
    'artifacts': artifacts, 'native': native, 'protocols': protocols,
    'project_version': capture('project_version', project_version),
    'processes': capture('pm2', pm2_status),
    'godot_version': capture('godot_version', lambda: version('/usr/local/bin/godot')),
    'node_version': capture('node_version', lambda: version(node)) if node else None,
    'legacy_supabase_absent': not (server/'supabase').exists() and not (server/'autoload/supabase_client.gd').exists(),
    'disk_free_bytes': capture('disk', lambda: shutil.disk_usage('/opt').free),
    'errors': errors,
}
print(json.dumps(result))
'''
    # No shell interpolation: the whole program is sent to python3 stdin.
    return "from pathlib import Path\nimport hashlib,json,re,shutil,subprocess\n" + helpers + "\npublic_paths = " + repr(paths) + "\n" + body


def request_public(base: str, path: str, method: str = "GET") -> dict:
    request = urllib.request.Request(base.rstrip("/") + path, method=method, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(request, timeout=30) as response:
        headers = {key: response.headers.get(key) for key in ("Content-Length", "Cache-Control", "Content-Type", "ETag", "Accept-Ranges")}
        body = response.read(1024 * 1024 + 1) if method == "GET" else b""
        if len(body) > 1024 * 1024:
            raise ValueError("Manifest exceeds expected metadata size")
        return {"status": response.status, "headers": headers, "data": json.loads(body) if body else None}


def collect_public(base: str, paths: list[str], method: str, report: dict) -> dict:
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(request_public, base, path, method): path for path in paths}
        for future in concurrent.futures.as_completed(futures):
            path = futures[future]
            try:
                results[path] = future.result()
            except Exception as error:
                report["errors"].append({"section": "public:" + path, "error_class": type(error).__name__})
    return results


def remote_audit(args: argparse.Namespace, paths: list[str]) -> dict:
    import paramiko
    client = paramiko.SSHClient()
    client.load_host_keys(str(args.known_hosts))
    client.set_missing_host_key_policy(paramiko.RejectPolicy())
    try:
        client.connect(args.host, port=args.port, username=args.user, key_filename=str(args.key_file),
                       allow_agent=False, look_for_keys=False, timeout=20, banner_timeout=20, auth_timeout=20)
        stdin, stdout, stderr = client.exec_command("python3 -", timeout=120)
        stdin.write(remote_audit_code(paths).encode("utf-8"))
        stdin.channel.shutdown_write()
        payload = stdout.read()
        status = stdout.channel.recv_exit_status()
        # Never print stderr; remote capture returns only operation/error class.
        stderr.read()
        if status != 0:
            raise RuntimeError("RemoteAuditProcessError")
        result = json.loads(payload)
        if not isinstance(result, dict):
            raise ValueError("RemoteAuditFormatError")
        return result
    finally:
        client.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", type=int, required=True)
    parser.add_argument("--mobile-version", required=True)
    parser.add_argument("--mobile-build", type=int)
    parser.add_argument("--launcher-build", type=int, required=True)
    parser.add_argument("--launcher-version")
    parser.add_argument("--protocol", help="Default: the source ClientNetwork protocol")
    parser.add_argument("--base-url", default="http://109.71.245.162")
    parser.add_argument("--host", default="109.71.245.162")
    parser.add_argument("--port", type=int, default=22)
    parser.add_argument("--user", default="root")
    parser.add_argument("--key-file", type=Path, default=Path.home() / ".ssh/bobux_deploy_ed25519")
    parser.add_argument("--known-hosts", type=Path, default=Path.home() / ".ssh/known_hosts")
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--skip-local-check", action="store_true", help="For auditing an older published release after local artifacts change")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version) or not re.fullmatch(r"\d+\.\d+\.\d+-mobile", args.mobile_version):
        parser.error("Expected desktop MAJOR.MINOR.PATCH and MAJOR.MINOR.PATCH-mobile")
    args.mobile_build = args.mobile_build if args.mobile_build is not None else args.build
    if min(args.build, args.mobile_build, args.launcher_build) < 1:
        parser.error("Build numbers must be positive")
    if args.launcher_version and not re.fullmatch(r"\d+\.\d+\.\d+", args.launcher_version):
        parser.error("Invalid launcher version")
    if not args.key_file.is_file() or not args.known_hosts.is_file():
        parser.error("Existing private key and pinned known_hosts are required")
    if args.protocol is None:
        source = (args.source_root / "autoload/client_network.gd").read_text(encoding="utf-8")
        match = re.search(r'const\s+NETWORK_PROTOCOL_VERSION\s*:\s*String\s*=\s*"([^"\n]+)"', source)
        if match is None: parser.error("Cannot resolve source protocol; provide --protocol")
        args.protocol = match.group(1)
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", args.protocol):
        parser.error("Invalid protocol identifier")
    args.output = args.output or args.source_root / f".codex-tmp/performance/release{args.build}-postdeploy-artifacts.json"
    return args


def audit(args: argparse.Namespace) -> dict:
    report = {"checked_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "read_only": True,
              "expected": {"version": args.version, "build": args.build, "mobile_version": args.mobile_version,
                           "mobile_build": args.mobile_build, "launcher_build": args.launcher_build, "protocol": args.protocol},
              "checks": [], "errors": []}
    def check(ok: bool, label: str, **details):
        report["checks"].append({"label": label, "ok": bool(ok), **details})
        if not ok: report["errors"].append({"section": label, "error_class": "CheckFailed"})
    manifest_paths = ["/launcher/latest.json", "/downloads/latest.json", "/mobile/latest.json", "/downloads/desktop-latest.json", "/api/health"]
    responses = collect_public(args.base_url, manifest_paths, "GET", report)
    for path, response in responses.items():
        if path.endswith(".json"):
            check(response["status"] == 200 and "no-store" in (response["headers"]["Cache-Control"] or "").lower(), "manifest cache:" + path, status=response["status"], cache_control=response["headers"]["Cache-Control"])
        else:
            check(response["status"] == 200 and isinstance(response["data"], dict) and response["data"].get("ok") is True, "API health", status=response["status"])
    if len(responses) != len(manifest_paths): return report
    try:
        windows = responses["/launcher/latest.json"]["data"]
        mobile = responses["/mobile/latest.json"]["data"]
        desktop = responses["/downloads/desktop-latest.json"]["data"]
        check(windows == responses["/downloads/latest.json"]["data"], "Windows manifest aliases match")
        check((windows["version"], windows["build"]) == (args.version, args.build), "Windows version/build")
        check((mobile["version"], mobile["build"], mobile["android"]["version"], mobile["android"]["build"]) == (args.mobile_version, args.mobile_build, args.mobile_version, args.mobile_build), "Android version/build")
        check((desktop["version"], desktop["build"]) == (args.version, args.build), "Desktop version/build")
        check(windows["launcher"]["build"] == args.launcher_build and (args.launcher_version is None or windows["launcher"]["version"] == args.launcher_version), "Launcher version/build")
        base = args.base_url.rstrip("/")
        windows_versioned = f"/downloads/Bobux-Windows-{args.version}-build{args.build}.zip"
        mobile_versioned = f"/mobile/Bobux-Android-{args.mobile_version}-build{args.mobile_build}.apk"
        launcher_versioned = f"/downloads/BobuxLauncher-Windows-{windows['launcher']['version']}-build{windows['launcher']['build']}.zip"
        check(windows["zip_url"] == base + windows_versioned and windows["launcher"]["zip_url"] in {base + "/downloads/BobuxLauncher-Windows.zip", base + launcher_versioned}, "Windows and launcher URLs")
        check(mobile["android"]["apk_url"] == base + "/mobile/Bobux-Android.apk" and mobile["android"]["versioned_apk_url"] == base + mobile_versioned, "Android stable and versioned URLs")
        check(desktop["platforms"]["windows"]["url"] == "/downloads/BobuxSetup.exe" and desktop["platforms"]["linux"]["url"] == "/downloads/Bobux-x86_64.AppImage", "Desktop installer URLs")
        release = args.source_root / "dist/release"
        artifacts = {
            "/downloads/Bobux-Windows.zip": (windows["sha256"], release / "Bobux-Windows.zip", windows.get("package_size")),
            windows_versioned: (windows["sha256"], release / windows_versioned.rsplit("/", 1)[1], windows.get("package_size")),
            "/downloads/BobuxLauncher-Windows.zip": (windows["launcher"]["sha256"], args.source_root / "dist/BobuxLauncher-Windows.zip", windows["launcher"].get("package_size")),
            "/mobile/Bobux-Android.apk": (mobile["android"]["sha256"], release / "Bobux-Android.apk", mobile["android"].get("package_size")),
            mobile_versioned: (mobile["android"]["sha256"], release / mobile_versioned.rsplit("/", 1)[1], mobile["android"].get("package_size")),
            "/downloads/BobuxSetup.exe": (desktop["platforms"]["windows"]["sha256"], release / "BobuxSetup.exe", desktop["platforms"]["windows"].get("size")),
            "/downloads/Bobux-x86_64.AppImage": (desktop["platforms"]["linux"]["sha256"], release / "Bobux-x86_64.AppImage", desktop["platforms"]["linux"].get("size")),
        }
        if windows["launcher"]["zip_url"] == base + launcher_versioned:
            artifacts[launcher_versioned] = (windows["launcher"]["sha256"], args.source_root / "dist/BobuxLauncher-Windows.zip", windows["launcher"].get("package_size"))
        for digest, _, _ in artifacts.values():
            if not isinstance(digest, str) or not re.fullmatch(r"[A-Fa-f0-9]{64}", digest):
                raise ValueError("Invalid manifest digest")
    except Exception as error:
        report["errors"].append({"section": "manifest structure", "error_class": type(error).__name__})
        return report
    heads = collect_public(args.base_url, list(artifacts), "HEAD", report)
    try:
        remote = remote_audit(args, list(artifacts))
    except Exception as error:
        report["errors"].append({"section": "SSH audit", "error_class": type(error).__name__})
        return report
    report["server"] = remote
    report["errors"].extend(remote.get("errors", []))
    for path, (expected, local, manifest_size) in artifacts.items():
        identity = remote.get("artifacts", {}).get(path)
        head = heads.get(path)
        if identity is None or head is None: continue
        try:
            length = int(head["headers"]["Content-Length"])
            check(head["status"] == 200 and length == identity["size"], "artifact HTTP size:" + path, size=identity["size"], status=head["status"])
            check(identity["sha256"].lower() == expected.lower(), "artifact manifest SHA:" + path, sha256=identity["sha256"])
            if manifest_size is not None: check(identity["size"] == int(manifest_size), "artifact manifest size:" + path)
            stable = path not in {windows_versioned, mobile_versioned, launcher_versioned}
            policy = (head["headers"]["Cache-Control"] or "").lower()
            check("no-store" in policy if stable else bool(policy), "artifact cache:" + path, cache_control=policy, stable=stable)
            if not args.skip_local_check and local.is_file():
                check(sha256_file(local).lower() == expected.lower(), "artifact local SHA:" + path)
            else:
                report["checks"].append({"label": "artifact local SHA:" + path, "ok": None, "skipped": "explicit" if args.skip_local_check else "no local artifact"})
        except Exception as error:
            report["errors"].append({"section": "artifact:" + path, "error_class": type(error).__name__})
    for name, identity in remote.get("native", {}).items():
        if identity is not None:
            local = args.source_root / "addons/luaAPI/bin" / name
            try: check(identity["sha256"] == sha256_file(local) and identity["size"] == local.stat().st_size, "server native:" + name)
            except Exception as error: report["errors"].append({"section": "native:" + name, "error_class": type(error).__name__})
    check(set(remote.get("protocols", {})) == {"autoload/client_network.gd", "server/server_main.gd"} and all(value == args.protocol for value in remote.get("protocols", {}).values()), "server network protocol")
    check(remote.get("project_version") == args.version, "server project version")
    check(remote.get("legacy_supabase_absent") is True, "legacy Supabase retired")
    processes = remote.get("processes") or []
    check(len(processes) == 2 and {item["name"] for item in processes} == {"bobux", "bobux-api"} and all(item["status"] == "online" for item in processes), "PM2 game and API online")
    return report


def main() -> int:
    args = parse_args()
    try:
        report = audit(args)
    except Exception as error:
        report = {"read_only": True, "checks": [], "errors": [{"section": "audit", "error_class": type(error).__name__}]}
    report["passed"] = not report["errors"]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("Release artifacts PASS=", report["passed"], "checks=", len(report["checks"]), "report=", args.output)
    for error in report["errors"]:
        print(error["section"], error["error_class"])
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
