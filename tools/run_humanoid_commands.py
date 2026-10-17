"""Exercise typed production Humanoid RPCs with an isolated server and two rooms."""
from pathlib import Path
import subprocess
import time

root = Path(__file__).resolve().parents[1]
godot = root / ".codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe"
output = root / ".codex-tmp/humanoid_commands"
output.mkdir(parents=True, exist_ok=True)
marker = output / "server-ready"
marker.unlink(missing_ok=True)
processes, streams = [], []

def launch(label, *args):
    stream = (output / f"{label}.log").open("w", encoding="utf-8")
    streams.append(stream)
    command = [str(godot), "--headless", "--path", str(root), "--script", "res://tools/validate_humanoid_commands.gd", "--", *args]
    process = subprocess.Popen(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    processes.append((label, process))

try:
    launch("server", "--server")
    until = time.monotonic() + 15
    while not marker.exists() and time.monotonic() < until:
        time.sleep(0.1)
    if not marker.exists():
        raise RuntimeError("Humanoid RPC server did not start; inspect server.log")
    launch("client-a")
    launch("client-b", "--room-b")
    codes = []
    for label, process in processes:
        code = process.wait(timeout=45)
        codes.append(code)
        log = (output / f"{label}.log").read_text(encoding="utf-8", errors="replace")
        if "SCRIPT ERROR:" in log or "\nERROR:" in log:
            codes.append(1)
        print(label, "exit=", code, flush=True)
    raise SystemExit(0 if all(code == 0 for code in codes) else 1)
finally:
    for _, process in processes:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
    for stream in streams:
        stream.close()
