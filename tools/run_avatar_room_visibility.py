"""Launch the four-process room visibility regression without live accounts."""
import argparse
import os
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("--godot", required=True)
args = parser.parse_args()
workspace = Path(__file__).resolve().parents[1]
output = workspace / ".codex-tmp/performance/avatar-visibility"
output.mkdir(parents=True, exist_ok=True)
marker = workspace / ".codex-tmp/avatar-visibility-ready"
marker.unlink(missing_ok=True)
processes = []
handles = []
try:
    for name, flags in [("server", ["--server"]), ("a1", []), ("a2", []), ("b", ["--other"])]:
        appdata = output / name
        appdata.mkdir(exist_ok=True)
        env = dict(os.environ, APPDATA=str(appdata))
        log = (output / f"{name}.log").open("w", encoding="utf-8")
        handles.append(log)
        command = [args.godot, "--headless", "--path", str(workspace), "--script", "res://tools/validate_avatar_room_visibility.gd", "--", *flags]
        processes.append((name, subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)))
        if name == "server":
            ready_until = time.monotonic() + 20
            while not marker.exists() and time.monotonic() < ready_until:
                if processes[-1][1].poll() is not None: break
                time.sleep(.1)
            if not marker.exists(): raise RuntimeError("Isolated server did not bind its port")
    deadline = time.monotonic() + 40
    for name, process in processes:
        process.wait(timeout=max(0.1, deadline - time.monotonic()))
        print(f"{name}: exit={process.returncode}, log={output / (name + '.log')}")
    for log in handles: log.flush()
    errors = []
    for name, _ in processes:
        body = (output / f"{name}.log").read_text(encoding="utf-8", errors="replace")
        if "SCRIPT ERROR:" in body or "ERROR:" in body:
            errors.append(name)
    if errors: print("Runtime errors in logs:", ", ".join(errors))
    raise SystemExit(0 if not errors and all(process.returncode == 0 for _, process in processes) else 1)
finally:
    for _, process in processes:
        if process.poll() is None:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill()
    for log in handles: log.close()
