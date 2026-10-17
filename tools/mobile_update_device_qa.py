"""Small, non-destructive ADB controls for final Bobux release QA.

Uses the existing game account and never clears its data. Screenshots and a
redacted process-scoped log live under .codex-tmp/mobile_update_qa/fullgame.
"""
from pathlib import Path
import argparse
import json
import re
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".codex-tmp/mobile_update_qa/fullgame"
ADB = Path(r"C:\Users\Pavel\AppData\Local\Android\Sdk\platform-tools\adb.exe")
SERIAL = "USNNU20612102367"
PACKAGE = "com.bobux.game"
FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def adb(*args, timeout=30, binary=False):
    result = subprocess.run([str(ADB), "-s", SERIAL, *map(str, args)],
                            capture_output=True, timeout=timeout, creationflags=FLAGS)
    if result.returncode and tuple(map(str, args[:2])) == ("shell", "pidof"):
        return ""
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", "replace")[-1000:])
    return result.stdout if binary else result.stdout.decode("utf-8", "replace").strip()


def redact(value):
    value = re.sub(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b", "[JWT redacted]", value)
    return re.sub(r"(?i)(access_token|refresh_token|password|authorization)([\"\s:=]+)([^\s,}\"]+)",
                  r"\1\2[redacted]", value)


def capture(name):
    if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
        raise ValueError("Screenshot name must be a plain identifier")
    OUT.mkdir(parents=True, exist_ok=True)
    data = adb("exec-out", "screencap", "-p", binary=True)
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("Expected a PNG from screencap")
    (OUT / (name + ".png")).write_bytes(data)
    return {"path": str(OUT / (name + ".png")), "size": struct.unpack(">II", data[16:24])}


def main():
    global OUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["snapshot", "launch", "restart", "tap", "swipe", "log", "info", "install", "premiere"])
    parser.add_argument("values", nargs="*")
    parser.add_argument("--run-name", help="Preserve separate evidence for each APK revision")
    args = parser.parse_args()
    if args.run_name:
        if not re.fullmatch(r"[A-Za-z0-9_-]+", args.run_name):
            parser.error("run-name must be a plain identifier")
        OUT = OUT / args.run_name
    OUT.mkdir(parents=True, exist_ok=True)
    if args.action == "snapshot":
        print(json.dumps(capture(args.values[0]), ensure_ascii=False))
    elif args.action in ["launch", "restart"]:
        if args.action == "restart":
            adb("shell", "am", "force-stop", PACKAGE)
        print(adb("shell", "am", "start", "-n", PACKAGE + "/com.godot.game.GodotAppLauncher"))
    elif args.action == "tap":
        if len(args.values) != 2 or any(not value.isdigit() for value in args.values):
            parser.error("tap requires observed integer x y")
        print(adb("shell", "input", "tap", *args.values))
    elif args.action == "swipe":
        if len(args.values) not in [4, 5] or any(not value.isdigit() for value in args.values):
            parser.error("swipe requires observed integer x1 y1 x2 y2 [milliseconds]")
        print(adb("shell", "input", "swipe", *args.values))
    elif args.action == "log":
        pid = adb("shell", "pidof", PACKAGE)
        if not re.fullmatch(r"\d+", pid):
            raise RuntimeError("Bobux is not running")
        data = redact(adb("logcat", "-d", "--pid=" + pid, "-v", "brief", "-T", "5000"))
        (OUT / "game_logcat.log").write_text(data, encoding="utf-8")
        critical = [line for line in data.splitlines() if any(value in line for value in
                    ["ERROR:", "SCRIPT ERROR", "Parse Error", "FATAL EXCEPTION", "Connection failed", "Connection established", "Authenticated", "Cannot", "ERR_OUT_OF_MEMORY"]) ]
        print(json.dumps({"path": str(OUT / "game_logcat.log"), "critical": critical[-60:]}, ensure_ascii=False))
    elif args.action == "info":
        report = {"serial": SERIAL, "model": adb("shell", "getprop", "ro.product.model"),
                  "package": "\n".join(line.strip() for line in adb("shell", "dumpsys", "package", PACKAGE).splitlines()
                                         if any(value in line for value in ["versionCode=", "versionName=", "primaryCpuAbi="])),
                  "focus": "\n".join(line.strip() for line in adb("shell", "dumpsys", "window", "windows").splitlines()
                                       if "mCurrentFocus=" in line or "mFocusedApp=" in line),
                  "pid": adb("shell", "pidof", PACKAGE)}
        (OUT / "device_state.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False))
    elif args.action == "install":
        apk = Path(args.values[0]).resolve()
        if not apk.is_file() or apk.suffix != ".apk":
            parser.error("install requires an existing signed APK")
        # Explicit staging avoids an ambiguous streaming result when Godot's
        # export process releases its ADB daemon during pipeline completion.
        staged = "/data/local/tmp/bobux-update-final-qa.apk"
        print(adb("push", str(apk), staged, timeout=120), flush=True)
        result = adb("shell", "pm", "install", "-r", staged, timeout=240)
        if result.strip() != "Success":
            raise RuntimeError("Package manager did not confirm install: " + result)
        print(result, flush=True)
        adb("shell", "rm", staged)
    elif args.action == "premiere":
        # First use only: never edits the trailer's per-account acknowledgement.
        adb("shell", "am", "force-stop", PACKAGE)
        print(adb("shell", "am", "start", "-n", PACKAGE + "/com.godot.game.GodotAppLauncher"), flush=True)
        started = time.monotonic()
        screenshots = []
        for seconds, name in [(0.8, "premiere_initial"), (4.0, "premiere_sad"),
                              (12.0, "premiere_phone"), (20.0, "premiere_magic"),
                              (27.0, "premiere_happy"), (31.0, "premiere_logo"),
                              (38.0, "premiere_return_lobby"), (43.0, "premiere_lobby_loaded"),
                              (55.0, "premiere_late_return"), (65.0, "premiere_final_lobby")]:
            time.sleep(max(0, seconds - (time.monotonic() - started)))
            if not adb("shell", "pidof", PACKAGE):
                raise RuntimeError("Bobux exited during the premiere")
            screenshots.append(dict(capture(name), wall_seconds=round(time.monotonic() - started, 3)))
            print("ANDROID_PREMIERE_CAPTURE=" + name, flush=True)
        pid = adb("shell", "pidof", PACKAGE)
        log = redact(adb("logcat", "-d", "--pid=" + pid, "-v", "brief", "-T", "5000"))
        (OUT / "premiere_logcat.log").write_text(log, encoding="utf-8")
        errors = [line for line in log.splitlines() if any(value in line for value in
                  ["ERROR:", "SCRIPT ERROR", "Parse Error", "FATAL EXCEPTION", "ERR_OUT_OF_MEMORY", "Playback did not start"])]
        memory = adb("shell", "dumpsys", "meminfo", PACKAGE)
        (OUT / "premiere_meminfo.txt").write_text(memory, encoding="utf-8")
        report = {"serial": SERIAL, "package": PACKAGE, "process_alive": bool(pid),
                  "captures": screenshots, "errors": errors, "visual_review_required": True}
        (OUT / "premiere_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print("ANDROID_PREMIERE_REPORT=" + json.dumps({key: value for key, value in report.items() if key != "captures"}, ensure_ascii=False), flush=True)
        if errors:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
