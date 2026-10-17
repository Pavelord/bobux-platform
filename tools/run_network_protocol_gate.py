"""Run the real protocol handshake without live rooms, credentials or accounts."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import time

# Windows CI may provide a cp1252 pipe; rejection diagnostics include Unicode.
# Keep the console UTF-8 like the captured Godot logs, without dropping text.
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, 'reconfigure'):
        stream.reconfigure(encoding='utf-8', errors='backslashreplace')

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
args = parser.parse_args()
workspace = Path(__file__).resolve().parents[1]
output = workspace / '.codex-tmp/performance/protocol-gate'
output.mkdir(parents=True, exist_ok=True)
for name in ('ready', 'clients-done'):
    (output / name).unlink(missing_ok=True)
handles = []
processes = []

def start(name, flags):
    appdata = output / name
    appdata.mkdir(exist_ok=True)
    log = (output / (name + '.log')).open('w', encoding='utf-8')
    handles.append(log)
    command = [args.godot, '--headless', '--path', str(workspace), '--script',
               'res://tools/validate_network_protocol_gate.gd', '--', *flags]
    process = subprocess.Popen(command, env=dict(os.environ, APPDATA=str(appdata)), stdout=log, stderr=subprocess.STDOUT)
    processes.append((name, process))
    return process

try:
    server = start('server', ['--server'])
    deadline = time.monotonic() + 15
    while not (output / 'ready').exists() and server.poll() is None and time.monotonic() < deadline:
        time.sleep(.05)
    if not (output / 'ready').exists():
        raise RuntimeError('Isolated protocol server did not start; inspect server.log')
    for name, flags in [('old', ['--old']), ('current', [])]:
        start(name, flags).wait(timeout=30)
    server.wait(timeout=30)
    for handle in handles:
        handle.flush()
    failed = []
    for name, process in processes:
        body = (output / (name + '.log')).read_text(encoding='utf-8')
        print(name, 'exit=', process.returncode, 'log=', output / (name + '.log'))
        for line in body.splitlines():
            if 'PROTOCOL_GATE_' in line or 'ERROR:' in line:
                print(line)
        if process.returncode != 0 or 'ERROR:' in body:
            failed.append(name)
    raise SystemExit(1 if failed else 0)
finally:
    for name, process in processes:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
    for handle in handles:
        handle.close()
