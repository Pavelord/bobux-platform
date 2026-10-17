"""Actual NDS controller + published map builder + two real network clients."""
from pathlib import Path
import os, subprocess, time, sys
root = Path(__file__).resolve().parents[1]
godot = root / '.codex-tools/godot-4.7/Godot_v4.7-stable_win64.exe'
marker = root / '.codex-tmp/nds-net-ready'
marker.unlink(missing_ok=True)
processes, files = [], []
def launch(label, *args):
    out = (root / f'.codex-tmp/nds-net-{label}.log').open('w', encoding='utf-8')
    files.append(out)
    fixture_appdata = root / '.codex-tmp/performance/nds-server-regression' / label
    env = dict(os.environ, APPDATA=str(fixture_appdata))
    proc = subprocess.Popen([str(godot), '--headless', '--path', str(root), '--log-file', str(root / f'.codex-tmp/nds-net-{label}-engine.log'), '--script', 'tools/validate_nds_multiplayer.gd', '--', *args], cwd=root, env=env, stdout=out, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    processes.append((label, proc))
try:
    launch('server', '--server', *sys.argv[1:])
    until = time.monotonic() + 65
    while not marker.exists() and time.monotonic()<until: time.sleep(.1)
    if not marker.exists(): raise RuntimeError('NDS server did not build map')
    launch('first', *sys.argv[1:])
    time.sleep(23)
    launch('late', '--late', *sys.argv[1:])
    codes=[]
    for label,proc in processes:
        code=proc.wait(timeout=235)
        codes.append(code)
        print(label, 'exit=', code, flush=True)
    for out in files: out.flush()
    errors = [label for label, _ in processes if 'ERROR:' in (root / f'.codex-tmp/nds-net-{label}.log').read_text(encoding='utf-8', errors='replace')]
    if errors: print('Runtime errors in logs:', ', '.join(errors), flush=True)
    raise SystemExit(0 if not errors and all(code==0 for code in codes) else 1)
finally:
    for _,proc in processes:
        if proc.poll() is None: proc.terminate(); proc.wait(timeout=10)
    for out in files: out.close()
