"""Exercise production seating through an isolated server and two clients."""
from pathlib import Path
import subprocess
import time

root = Path(__file__).resolve().parents[1]
godot = root / '.codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'
out_dir = root / '.codex-tmp/halloween/city-rp'
out_dir.mkdir(parents=True, exist_ok=True)
marker = out_dir / 'seat-server-ready'
marker.unlink(missing_ok=True)
processes, logs = [], []

def launch(label, *args):
    log = (out_dir / f'seat-{label}.log').open('w', encoding='utf-8')
    logs.append(log)
    command = [str(godot), '--headless', '--path', str(root), '--script', 'tools/validate_seat_authority.gd', '--', *args]
    process = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    processes.append((label, process))

try:
    launch('server', '--server')
    deadline = time.monotonic() + 15
    while not marker.exists() and time.monotonic() < deadline: time.sleep(0.1)
    if not marker.exists(): raise RuntimeError('Seat fixture server did not start; inspect seat-server.log')
    launch('first')
    launch('second')
    codes = []
    for label, process in processes:
        code = process.wait(timeout=45)
        codes.append(code)
        output = (out_dir / f'seat-{label}.log').read_text(encoding='utf-8', errors='replace')
        if 'SCRIPT ERROR:' in output or '\nERROR:' in output:
            codes.append(1)
            print(label, 'Godot errors in log', flush=True)
        print(label, 'exit=', code, flush=True)
    raise SystemExit(0 if all(code == 0 for code in codes) else 1)
finally:
    for _, process in processes:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
    for log in logs: log.close()
