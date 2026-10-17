"""Install the isolated trailer APK and measure real playback on the authorized phone."""
from pathlib import Path
import json
import queue
import re
import struct
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / ".codex-tmp/mobile_update_trailer_probe"
OUT = ROOT / ".codex-tmp/mobile_update_qa/trailer"
OUT.mkdir(parents=True, exist_ok=True)
ADB = Path(r"C:\Users\Pavel\AppData\Local\Android\Sdk\platform-tools\adb.exe")
SERIAL = "USNNU20612102367"
PACKAGE = "com.bobux.trailerqa"
FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0)

def adb(*args, timeout=30, binary=False):
    result = subprocess.run([str(ADB), "-s", SERIAL, *args], capture_output=True, timeout=timeout, creationflags=FLAGS)
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", "replace")[-1000:])
    return result.stdout if binary else result.stdout.decode("utf-8", "replace").strip()

def capture(name):
    data = adb("exec-out", "screencap", "-p", binary=True)
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("Device screenshot did not return PNG")
    (OUT / (name + ".png")).write_bytes(data)
    return struct.unpack(">II", data[16:24])

print(adb("install", "-r", str(PROBE / "Bobux-Trailer-QA.apk"), timeout=90), flush=True)
adb("shell", "am", "force-stop", PACKAGE)
print(adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1"), flush=True)
pid = adb("shell", "pidof", PACKAGE)
if not re.fullmatch(r"\d+", pid):
    raise RuntimeError("Probe did not start")
logcat = subprocess.Popen([str(ADB), "-s", SERIAL, "logcat", "--pid=" + pid, "-v", "brief", "-T", "1"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=FLAGS)
lines = queue.Queue()

def reader():
    for line in iter(logcat.stdout.readline, b""):
        lines.put(line.decode("utf-8", "replace").rstrip())

thread = threading.Thread(target=reader, daemon=True)
thread.start()
records = []
captured = set()
started = time.monotonic()
backgrounded = False
resumed = False
skip_tapped = False
result = None
try:
    while time.monotonic() - started < 65:
        elapsed = time.monotonic() - started
        while not lines.empty():
            line = lines.get_nowait()
            records.append(line)
            if "MOBILE_UPDATE_TRAILER_" in line or "SCRIPT ERROR" in line or "FATAL EXCEPTION" in line:
                print(line, flush=True)
            if "MOBILE_UPDATE_TRAILER_SKIP_READY=" in line:
                payload = json.loads(line.split("MOBILE_UPDATE_TRAILER_SKIP_READY=", 1)[1])
                capture("replay_before_touch_skip")
                adb("shell", "input", "tap", str(round(payload["physical_x"])), str(round(payload["physical_y"])))
                skip_tapped = True
            if "MOBILE_UPDATE_TRAILER_RESULT=" in line:
                result = json.loads(line.split("MOBILE_UPDATE_TRAILER_RESULT=", 1)[1])
        for seconds, name in [(3.0, "sad_room"), (14.0, "phone_magic"), (20.0, "halloween_room"), (27.0, "happy_actor"), (31.0, "final_logo")]:
            if elapsed > seconds and name not in captured:
                capture(name)
                captured.add(name)
        if elapsed > 8.0 and not backgrounded:
            adb("shell", "input", "keyevent", "KEYCODE_HOME")
            backgrounded = True
            print("ADB_REAL_APPLICATION_PAUSE", flush=True)
        if elapsed > 10.0 and backgrounded and not resumed:
            adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1")
            resumed = True
            print("ADB_REAL_APPLICATION_RESUME", flush=True)
        if result is not None:
            capture("completed_lobby")
            break
        time.sleep(0.1)
finally:
    logcat.terminate()
    logcat.communicate(timeout=10)
    (OUT / "logcat.log").write_text("\n".join(records), encoding="utf-8")
report = {"serial": SERIAL, "package": PACKAGE, "result": result, "lifecycle_real_home_resume": backgrounded and resumed, "skip_actual_adb_tap": skip_tapped, "apk_bytes": (PROBE / "Bobux-Trailer-QA.apk").stat().st_size}
(OUT / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("REAL_ANDROID_TRAILER_REPORT=" + json.dumps(report), flush=True)
raise SystemExit(0 if result and result.get("ok") else 1)
