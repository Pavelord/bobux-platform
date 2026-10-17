"""Install the isolated benchmark and retain ADB/logcat for the whole run."""
import argparse
import json
import pathlib
import subprocess
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument("--apk", required=True)
parser.add_argument("--output", required=True)
parser.add_argument("--port", type=int, default=17860)
parser.add_argument("--timeout", type=int, default=900)
args = parser.parse_args()
adb = r"C:\Users\Pavel\AppData\Local\Android\Sdk\platform-tools\adb.exe"
package = "com.bobux.performance"
output = pathlib.Path(args.output).resolve()
output.parent.mkdir(parents=True, exist_ok=True)

def run(*command, timeout=90):
    result = subprocess.run([adb, *command], capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", errors="replace")[-2000:])
    return result.stdout.decode("utf-8", errors="replace")

print(run("install", "-r", str(pathlib.Path(args.apk).resolve()), timeout=180).strip(), flush=True)
run("reverse", f"tcp:{args.port}", f"tcp:{args.port}")
run("shell", "input", "keyevent", "KEYCODE_WAKEUP")
run("shell", "wm", "dismiss-keyguard")
run("shell", "am", "force-stop", package)
records = {}
report_seen = threading.Event()
errors = []
fatal_error = threading.Event()
stream = subprocess.Popen([adb, "logcat", "-T", "1", "-v", "threadtime", "-s", "godot"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

def collect():
    with output.open("wb") as log:
        for line in iter(stream.stdout.readline, b""):
            log.write(line)
            log.flush()
            message = line.decode("utf-8", errors="replace").strip()
            for marker in ["[perf] RESULT ", "[perf] BATCH_AB "]:
                if marker not in message:
                    continue
                payload = message.split(marker, 1)[1]
                if marker.endswith("BATCH_AB "):
                    payload = payload[payload.index("{"):]
                try:
                    record = json.loads(payload)
                except (ValueError, json.JSONDecodeError):
                    continue
                key = (record["map"], record["run"])
                records.setdefault(key, {}).update(record)
                combined = records[key]
                print("[android]", combined["map"], "join_ms=", combined.get("join_ms"), "fps=", round(combined.get("frame", {}).get("fps", 0), 2), "batched=", round(combined.get("batched_frame", {}).get("fps", 0), 2), "failed=", combined.get("runtime", {}).get("failed"), flush=True)
            if "SCRIPT ERROR" in message or "ERR_OUT_OF_MEMORY" in message:
                errors.append(message)
                if "Parse Error" in message:
                    fatal_error.set()
            if "[perf] REPORT " in message:
                report_seen.set()

thread = threading.Thread(target=collect, daemon=True)
thread.start()
run("shell", "am", "start", "-n", package + "/com.godot.game.GodotAppLauncher")
started = time.monotonic()
try:
    while not report_seen.wait(5):
        if stream.poll() is not None:
            raise RuntimeError("ADB logcat ended; repeat the run after Android exports finish")
        if fatal_error.is_set():
            raise RuntimeError("Android diagnostic could not parse; see logcat")
        if time.monotonic() - started > args.timeout:
            raise TimeoutError("Android performance run timed out; see logcat")
        if not run("shell", "pidof", package).strip():
            break
finally:
    stream.terminate()
    thread.join(timeout=5)
    report = {"results": list(records.values()), "errors": errors, "report_seen": report_seen.is_set()}
    output.with_suffix(".json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("[android] finished", len(records), "records,", len(errors), "script/transport errors", flush=True)
if not report_seen.is_set() or errors:
    raise SystemExit(1)
