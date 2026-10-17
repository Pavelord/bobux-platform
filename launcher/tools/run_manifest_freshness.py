"""Local mirrors plus a real live Windows helper: no production requests or user data."""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading
import time
import zipfile

LAUNCHER = Path(__file__).resolve().parents[1]
WORKSPACE = LAUNCHER.parent
NONCE = "0123456789abcdef0123456789abcdef"
OLD_EXE = bytes([42]) * (11 * 1024 * 1024)
NEW_EXE = bytes([43]) * len(OLD_EXE)
RUNTIME = b"manifest guard native-runtime contract"

def package(executable: bytes) -> bytes:
    with io.BytesIO() as buffer:
        with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("Bobux.exe", executable)
            archive.writestr("runtime.bin", RUNTIME)
        return buffer.getvalue()

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    args = parser.parse_args()
    assert os.name == "nt", "The helper liveness contract uses a real Windows PowerShell process"
    folder = WORKSPACE / ".codex-tmp" / ("launcher-manifest-guard-" + str(os.getpid()))
    folder.mkdir(parents=True)
    old_zip, new_zip = package(OLD_EXE), package(NEW_EXE)
    def metadata(build: int, version: str, exe: bytes) -> dict:
        return {"build": build, "version": version, "executable": "Bobux.exe", "embedded_pck": True,
                "executable_size": len(exe), "executable_sha256": hashlib.sha256(exe).hexdigest(),
                "sha256": hashlib.sha256(new_zip).hexdigest(), "package_size": len(new_zip),
                "required_files": [{"path": "runtime.bin", "size": len(RUNTIME), "sha256": hashlib.sha256(RUNTIME).hexdigest()}]}
    current = metadata(58, "0.1.53", OLD_EXE)
    for name in ["fallback", "all_old", "equal", "newer"]:
        game = folder / name / "Game"
        game.mkdir(parents=True)
        (game / "Bobux.exe").write_bytes(OLD_EXE)
        (game / "runtime.bin").write_bytes(RUNTIME)
        marker = json.dumps({key: current[key] for key in ["version", "build", "executable_size", "executable_sha256"]})
        for path in [game / "version.json", game.parent / "version.json"]:
            path.write_text(marker, encoding="utf-8")
        cache = game.parent / "_download"
        cache.mkdir()
        (cache / "verified_prior.zip").write_bytes(old_zip)
    helper_script = folder / "live-helper.ps1"
    helper_info = folder / "live-helper.json"
    helper_script.write_text("param([string]$InfoPath)\n$p=[Diagnostics.Process]::GetCurrentProcess()\n@{ pid=$PID; ticks=$p.StartTime.ToUniversalTime().Ticks.ToString() } | ConvertTo-Json | Set-Content -LiteralPath $InfoPath -Encoding UTF8\nStart-Sleep -Seconds 120\n", encoding="utf-8")
    helper = subprocess.Popen(["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(helper_script), "-InfoPath", str(helper_info)], creationflags=subprocess.CREATE_NO_WINDOW)
    counts: Counter[str] = Counter()
    class Fixture(BaseHTTPRequestHandler):
        def log_message(self, *_args): pass
        def do_GET(self):
            counts[self.path] += 1
            if self.path == "/counts": value = dict(counts)
            elif self.path in ["/old", "/old-build", "/current", "/newer"]:
                version = "0.1.52" if self.path == "/old" else ("0.1.54" if self.path == "/newer" else "0.1.53")
                build = 59 if self.path == "/newer" else (57 if self.path in ["/old", "/old-build"] else 58)
                value = metadata(build, version, NEW_EXE if self.path == "/newer" else OLD_EXE)
                value["zip_url"] = f"http://127.0.0.1:{self.server.server_port}/package.zip"
                # A stale mirror even promises a launcher update: selection
                # must reject it before entering the self-update boundary.
                value["launcher"] = {"build": 99999, "zip_url": f"http://127.0.0.1:{self.server.server_port}/launcher.zip"}
            elif self.path == "/package.zip":
                self.send_response(200)
                self.send_header("Content-Type", "application/zip")
                self.send_header("Content-Length", str(len(new_zip)))
                self.end_headers()
                self.wfile.write(new_zip)
                return
            else: self.send_error(404); return
            payload = json.dumps(value).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        deadline = time.monotonic() + 15
        while not helper_info.exists():
            assert helper.poll() is None and time.monotonic() < deadline, "Fixture helper failed to start"
            time.sleep(0.025)
        # The writer closes its file before these public process metadata are used.
        info = json.loads(helper_info.read_text(encoding="utf-8-sig"))
        env = os.environ.copy()
        for name in list(env):
            if name.startswith("ROBLOXCLONE_CLOUD_") or name in ["BOBUX_SERVICE_KEY", "BOBUX_TEST_USER_ID"]: env.pop(name)
        env.update({"BOBUX_MANIFEST_FIXTURE_ROOT": str(folder), "BOBUX_DOWNLOAD_FIXTURE_URL": f"http://127.0.0.1:{server.server_port}",
                    "BOBUX_GUARD_HELPER_PID": str(info["pid"]), "BOBUX_GUARD_HELPER_TICKS": info["ticks"],
                    "APPDATA": str(folder / "appdata"), "LOCALAPPDATA": str(folder / "localappdata"), "TEMP": str(folder / "temp"), "TMP": str(folder / "temp")})
        for name in ["APPDATA", "LOCALAPPDATA", "TEMP"]: Path(env[name]).mkdir(parents=True)
        command = [str(args.godot.resolve()), "--headless", "--path", str(LAUNCHER), "--script", "res://tools/validate_manifest_freshness.gd"]
        for name, extra, result_marker in [("manifest", [], "MANIFEST_FRESHNESS_RESULT="), ("replacement", ["--", "--guard-replacement", "--launcher-handoff=" + NONCE], "MANIFEST_REPLACEMENT_RESULT=")]:
            run = subprocess.run(command + extra, env=env, capture_output=True, text=True, timeout=60)
            output = run.stdout + run.stderr
            (folder / (name + ".log")).write_text(output, encoding="utf-8")
            print(output, flush=True)
            assert run.returncode == 0 and result_marker in output and '"ok":true' in output
            assert not re.search(r"SCRIPT ERROR|^ERROR:", output, re.M)
        result = {"ok": True, "package_gets": counts["/package.zip"], "launcher_package_gets": counts["/launcher.zip"], "counts": dict(counts), "logs": str(folder)}
        (WORKSPACE / ".codex-tmp/manifest_freshness_result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        print("MANIFEST_AND_HANDOFF_GUARD_PASS", json.dumps(result), flush=True)
        for name in ["fallback", "all_old", "equal", "newer", "handoff", "appdata", "localappdata", "temp"]:
            path = (folder / name).resolve()
            path.relative_to((WORKSPACE / ".codex-tmp").resolve())
            if path.is_dir(): shutil.rmtree(path)
        return 0
    finally:
        helper.terminate()
        helper.wait(timeout=10)
        server.shutdown()
        server.server_close()

if __name__ == "__main__": raise SystemExit(main())
