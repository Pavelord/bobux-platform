"""Exercise the real Godot downloader against a local HTTP fixture only."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import subprocess
import threading
import time
import zipfile
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

RANGE_BYTES = bytes([37]) * (17 * 1024 * 1024 + 123)
SLOW_BYTES = bytes([91]) * (3 * 1024 * 1024)
COUNTS: Counter[str] = Counter()
EXE_BYTES = bytes([42]) * (11 * 1024 * 1024)
with io.BytesIO() as buffer:
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("Bobux.exe", EXE_BYTES)
        archive.writestr("runtime.bin", b"verified native runtime fixture")
    INSTALL_ZIP = buffer.getvalue()


class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *_args: object) -> None:
        pass

    def do_GET(self) -> None:
        COUNTS[self.path] += 1
        if self.path == "/manifest":
            value = {
                "version": "0.1.99", "build": 99, "executable": "Bobux.exe",
                "embedded_pck": True, "executable_size": len(EXE_BYTES),
                "executable_sha256": hashlib.sha256(EXE_BYTES).hexdigest(),
                "zip_url": f"http://127.0.0.1:{self.server.server_port}/install.zip",
                "sha256": hashlib.sha256(INSTALL_ZIP).hexdigest(), "package_size": len(INSTALL_ZIP),
                "required_files": [{"path": "runtime.bin", "size": 31,
                                    "sha256": hashlib.sha256(b"verified native runtime fixture").hexdigest()}],
            }
            payload = json.dumps(value).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if self.path in ("/metadata", "/counts"):
            value = dict(COUNTS) if self.path == "/counts" else {
                "range_size": len(RANGE_BYTES),
                "range_hash": hashlib.sha256(RANGE_BYTES).hexdigest(),
                "slow_size": len(SLOW_BYTES),
                "slow_hash": hashlib.sha256(SLOW_BYTES).hexdigest(),
            }
            payload = json.dumps(value).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        slow = self.path in ("/slow", "/legacy-slow")
        full = slow or self.path in ("/ignore", "/corrupt")
        payload = INSTALL_ZIP if self.path == "/install.zip" else (SLOW_BYTES if slow else RANGE_BYTES)
        if self.path == "/corrupt":
            payload = bytes([38]) * len(payload)
        start, end = 0, len(payload) - 1
        if not full:
            match = re.fullmatch(r"bytes=(\d+)-(\d+)", self.headers.get("Range", ""))
            assert match, "fixture expects a bounded Range request"
            start, end = int(match[1]), min(int(match[2]), end)
        self.send_response(200 if full else 206)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(end - start + 1))
        if not full:
            advertised_start = start + 1 if self.path == "/wrong-range" else start
            self.send_header("Content-Range", f"bytes {advertised_start}-{end}/{len(payload)}")
        self.end_headers()
        try:
            if self.path == "/interrupt" and COUNTS[self.path] == 1:
                self.wfile.write(payload[start:start + 65536])
                self.wfile.flush()
                self.close_connection = True
                return
            for offset in range(start, end + 1, 128 * 1024):
                self.wfile.write(payload[offset:min(end + 1, offset + 128 * 1024)])
                self.wfile.flush()
                if slow:
                    time.sleep(0.035)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    args = parser.parse_args()
    launcher_root = Path(__file__).resolve().parents[1]
    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = os.environ.copy()
    env["BOBUX_DOWNLOAD_FIXTURE_URL"] = f"http://127.0.0.1:{server.server_port}"
    try:
        return subprocess.run(
            [str(args.godot.resolve()), "--headless", "--path", str(launcher_root),
             "--script", "res://tools/validate_download_contract.gd"],
            env=env, timeout=60, check=False,
        ).returncode
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    raise SystemExit(main())
