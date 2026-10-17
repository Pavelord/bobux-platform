"""Real release archive over loopback, a real Windows file lock, restart and native Luau."""
from __future__ import annotations
import argparse
from collections import Counter
import ctypes
from ctypes import wintypes
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import threading
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parent

def digest(path: Path) -> str:
    with path.open("rb") as stream: return hashlib.file_digest(stream, "sha256").hexdigest()

def safe_remove(path: Path) -> None:
    resolved = path.resolve()
    resolved.relative_to((WORKSPACE / ".codex-tmp").resolve())
    if resolved.exists(): shutil.rmtree(resolved)

class WindowsLock:
    def __init__(self) -> None:
        self.handle = None
        self.api = ctypes.WinDLL("kernel32", use_last_error=True)
        self.api.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        self.api.CreateFileW.restype = wintypes.HANDLE
        self.api.CloseHandle.argtypes = [wintypes.HANDLE]
        self.api.CloseHandle.restype = wintypes.BOOL
    def acquire(self, path: Path, share: int = 0) -> None:
        assert self.handle is None
        handle = self.api.CreateFileW(str(path), 0x80000000, share, None, 3, 0x80, None)
        if handle == ctypes.c_void_p(-1).value: raise ctypes.WinError(ctypes.get_last_error())
        self.handle = handle
    def release(self) -> None:
        if self.handle is not None:
            self.api.CloseHandle(self.handle)
            self.handle = None

def prepare_previous(archive_path: Path, install: Path) -> None:
    game = install / "Game"
    game.mkdir(parents=True)
    with zipfile.ZipFile(archive_path) as archive:
        for item in archive.infolist():
            output = (game / item.filename).resolve()
            output.relative_to(game.resolve())
            if item.is_dir(): output.mkdir(parents=True, exist_ok=True); continue
            output.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(item) as source, output.open("wb") as target: shutil.copyfileobj(source, target, 1024 * 1024)
    # A prior marker forces update; its original executable/runtime are real,
    # checksum-verified package bytes, rather than a toy ZIP or fake executable.
    marker = {"version": "0.1.52", "build": 57}
    for path in [install / "version.json", game / "version.json"]: path.write_text(json.dumps(marker), encoding="utf-8")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, default=WORKSPACE / "game/launcher/latest.json")
    parser.add_argument("--archive", type=Path, default=WORKSPACE / "dist/release/Bobux-Windows-0.1.53-build58.zip")
    parser.add_argument("--keep", action="store_true")
    parser.add_argument("--skip-secondary", action="store_true", help="Only for reproducing the old launcher before its instance guard exists")
    args = parser.parse_args()
    assert os.name == "nt", "This fixture uses a genuine Windows file lock"
    folder = WORKSPACE / ".codex-tmp" / ("launcher-full-package-" + str(os.getpid()))
    install = folder / "Install с пробелом"
    folder.mkdir(parents=True)
    manifest = json.loads(args.manifest.read_text(encoding="utf-8-sig"))
    assert manifest["build"] == 58
    assert args.archive.stat().st_size == manifest["package_size"] and digest(args.archive) == manifest["sha256"].lower()
    with zipfile.ZipFile(args.archive) as archive:
        for item in manifest["required_files"]:
            assert archive.getinfo(item["path"]).file_size == item["size"]
            with archive.open(item["path"]) as source: assert hashlib.file_digest(source, "sha256").hexdigest() == item["sha256"].lower()
        native_path = "addons/luaAPI/bin/libbobuxluau.windows.template_release.x86_32.dll"
        native = archive.read(native_path)
        offset = struct.unpack_from("<I", native, 0x3C)[0]
        assert native[:2] == b"MZ" and native[offset:offset+4] == b"PE\0\0" and struct.unpack_from("<H", native, offset+4)[0] == 0x14C
    print("FULL_PACKAGE_PREFLIGHT_OK:", args.archive.stat().st_size, "bytes; actual manifest + required hashes + native x86_32", flush=True)
    prepare_previous(args.archive, install)
    counts: Counter[str] = Counter()
    count_lock = threading.Lock()
    request_started = threading.Event()
    windows_lock = WindowsLock()
    class Fixture(BaseHTTPRequestHandler):
        def log_message(self, *_args): pass
        def do_GET(self):
            route = self.path.split("?", 1)[0]
            with count_lock: counts[route] += 1
            if route == "/lock":
                try: windows_lock.acquire(install / "Game/Bobux.exe"); value = {"ok": True}
                except OSError as error: value = {"ok": False, "error": str(error)}
            elif route in ["/lock-part", "/lock-zip"]:
                try:
                    suffix = ".zip.part" if route == "/lock-part" else ".zip"
                    candidates = list((install / "_download").glob("game_*" + suffix))
                    assert len(candidates) == 1
                    # .part remains readable but cannot be renamed. The final
                    # ZIP is fully unreadable, like a brief antivirus scan.
                    windows_lock.acquire(candidates[0], 1 if route == "/lock-part" else 0)
                    value = {"ok": True}
                except (OSError, AssertionError) as error: value = {"ok": False, "error": str(error)}
            elif route == "/unlock": windows_lock.release(); value = {"ok": True}
            elif route == "/manifest":
                value = dict(manifest)
                value["zip_url"] = f"http://127.0.0.1:{self.server.server_port}/full.zip"
                value["mirrors"] = [value["zip_url"]]
            elif route == "/counts":
                with count_lock: value = dict(counts)
            elif route == "/full.zip":
                request_started.set()
                total = args.archive.stat().st_size
                match = re.fullmatch(r"bytes=(\d+)-(\d+)", self.headers.get("Range", ""))
                start, end = (int(match[1]), min(int(match[2]), total - 1)) if match else (0, total - 1)
                assert 0 <= start <= end < total
                self.send_response(206 if match else 200)
                self.send_header("Content-Type", "application/zip")
                self.send_header("Content-Length", str(end - start + 1))
                if match: self.send_header("Content-Range", f"bytes {start}-{end}/{total}")
                self.end_headers()
                try:
                    with args.archive.open("rb") as source:
                        source.seek(start)
                        remaining = end - start + 1
                        while remaining:
                            data = source.read(min(1024 * 1024, remaining))
                            self.wfile.write(data)
                            self.wfile.flush()
                            with count_lock: counts["package_bytes"] += len(data)
                            remaining -= len(data)
                except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError): pass
                return
            else: self.send_error(404); return
            encoded = json.dumps(value).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    env = os.environ.copy()
    for name in list(env):
        if name.startswith("ROBLOXCLONE_CLOUD_") or name in ["BOBUX_SERVICE_KEY", "BOBUX_TEST_USER_ID"]: env.pop(name)
    env.update({"APPDATA": str(folder / "appdata"), "LOCALAPPDATA": str(folder / "localappdata"), "TEMP": str(folder / "temp"), "TMP": str(folder / "temp"),
                "BOBUX_DOWNLOAD_FIXTURE_URL": f"http://127.0.0.1:{server.server_port}", "BOBUX_FULL_PACKAGE_INSTALL_ROOT": str(install), "BOBUX_FULL_PACKAGE_SOURCE": str(args.archive.resolve())})
    for name in ["APPDATA", "LOCALAPPDATA", "TEMP"]: Path(env[name]).mkdir(parents=True, exist_ok=True)
    command = [str(args.godot.resolve()), "--headless", "--path", str(ROOT), "--script", "res://tools/validate_full_package_install.gd"]
    secondary = None
    try:
        with (folder / "installer.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 240
            while process.poll() is None and not request_started.wait(0.1):
                if time.monotonic() > deadline: process.kill(); raise TimeoutError("Installer did not start loopback download")
            if not args.skip_secondary and process.poll() is None:
                secondary = subprocess.run(command + ["--", "--secondary"], env=env, capture_output=True, text=True, timeout=45)
                (folder / "secondary.log").write_text(secondary.stdout + secondary.stderr, encoding="utf-8")
            try: code = process.wait(timeout=240)
            except subprocess.TimeoutExpired: process.kill(); process.wait(); raise
        output = (folder / "installer.log").read_text(encoding="utf-8", errors="replace")
        print(output[-18000:], flush=True)
        assert code == 0 and 'FULL_PACKAGE_INSTALL_RESULT={"' in output and '"ok":true' in output
        assert not re.search(r"SCRIPT ERROR|^ERROR:", output, re.M)
        if secondary is not None:
            assert secondary.returncode == 0 and '"ok":true' in secondary.stdout and 'FULL_PACKAGE_SECONDARY_RESULT=' in secondary.stdout, (secondary.stdout + secondary.stderr)[-4000:]
        smoke = subprocess.run([str(install / "Game/Bobux.exe"), "--headless", "--", "--verify-lua-runtime"], cwd=install / "Game", env=env, capture_output=True, text=True, timeout=90)
        (folder / "native_smoke.log").write_text(smoke.stdout + smoke.stderr, encoding="utf-8")
        assert smoke.returncode == 0 and "BOBUX_LUA_SMOKE_OK" in smoke.stdout, (smoke.stdout + smoke.stderr)[-5000:]
        assert not re.search(r"SCRIPT ERROR|^ERROR:", smoke.stdout + smoke.stderr, re.M)
        result = {"ok": True, "archive": args.archive.name, "archive_bytes": manifest["package_size"], "build": 58, "loopback_counts": dict(counts), "secondary_checked": secondary is not None, "native_luau": True, "logs": str(folder)}
        (WORKSPACE / ".codex-tmp/full_package_install_result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        print("FULL_PACKAGE_NATIVE_AND_INSTALL_PASS", json.dumps(result), flush=True)
        if not args.keep: safe_remove(install)
        return 0
    finally:
        windows_lock.release()
        server.shutdown()
        server.server_close()

if __name__ == "__main__": raise SystemExit(main())
