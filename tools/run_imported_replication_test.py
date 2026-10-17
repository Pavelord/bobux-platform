"""Run real server + two clients; the second joins an already-running round."""
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os, struct, subprocess, threading, time, zlib

root = Path(__file__).resolve().parents[1]
godot = root / '.codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'
temp_dir = root / '.codex-tmp'
temp_dir.mkdir(parents=True, exist_ok=True)
marker = temp_dir / 'replication-server-ready'
marker.unlink(missing_ok=True)
processes = []
files = []

def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

png = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 6, 0, 0, 0))
png += png_chunk(b"IDAT", zlib.compress((b"\x00\xff\x1a\xcc\xff\xff\x1a\xcc\xff" * 2))) + png_chunk(b"IEND", b"")

class AssetHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/net_texture.png":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(png)))
        self.end_headers()
        self.wfile.write(png)

    def log_message(self, *_args):
        pass

asset_server = ThreadingHTTPServer(("127.0.0.1", 0), AssetHandler)
asset_thread = threading.Thread(target=asset_server.serve_forever, daemon=True)
asset_thread.start()
os.environ["BOBUX_REPLICATION_ASSET_URL"] = f"http://127.0.0.1:{asset_server.server_address[1]}/net_texture.png"

def launch(label, *args):
    out = (temp_dir / f'replication-{label}.log').open('w', encoding='utf-8')
    files.append(out)
    command = [str(godot), '--headless', '--path', str(root), '--log-file', str(temp_dir / f'replication-{label}-engine.log'), '--script', 'tools/validate_imported_replication.gd', '--', '--trace-imported-network', *args]
    proc = subprocess.Popen(command, cwd=root, stdout=out, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    processes.append((label, proc))
    return proc

try:
    launch('server', '--server')
    until = time.monotonic() + 20
    while not marker.exists() and time.monotonic() < until:
        time.sleep(.1)
    if not marker.exists(): raise RuntimeError('Server did not start')
    launch('first')
    launch('other', '--other-room')
    time.sleep(8)
    launch('late', '--late')
    codes = []
    for label, proc in processes:
        code = proc.wait(timeout=45)
        codes.append(code)
        print(label, 'exit=', code, flush=True)
    raise SystemExit(0 if all(code == 0 for code in codes) else 1)
finally:
    for _, proc in processes:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=10)
    for file in files: file.close()
    asset_server.shutdown()
    asset_server.server_close()
