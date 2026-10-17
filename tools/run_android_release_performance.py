"""Run the isolated release-template Android benchmark with a private server.

Build the diagnostic APK first with five maps, --runs=1, --tag=android55 and
--server=ws://127.0.0.1:17860. This wrapper never exports or touches the user's
com.bobux.game app. It retains com.bobux.performance caches between runs.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import time

from run_pc_performance import (
    ROOT, MAPS, assert_guest_userdata, guest_environment, isolated_path,
    prepare_cache, sha256, stop_owned, validate_report, wait_server,
)

ADB = Path(r"C:\Users\Pavel\AppData\Local\Android\Sdk\platform-tools\adb.exe")
PACKAGE = "com.bobux.performance"


def adb_run(adb: Path, serial: str | None, *args: str) -> str:
    command = [str(adb)] + (["-s", serial] if serial else []) + list(args)
    result = subprocess.run(command, capture_output=True, timeout=30,
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    if result.returncode:
        raise RuntimeError("ADB command failed: " + result.stderr.decode("utf-8", errors="replace")[-1000:])
    return result.stdout.decode("utf-8", errors="replace").strip()


def device_serial(adb: Path, requested: str | None) -> str:
    devices = {}
    for line in adb_run(adb, None, "devices").splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 2:
            devices[fields[0]] = fields[1]
    if requested:
        if devices.get(requested) != "device":
            raise RuntimeError("Requested Android device is disconnected or has not authorized ADB")
        return requested
    available = [serial for serial, state in devices.items() if state == "device"]
    if len(available) != 1:
        raise RuntimeError("Specify --serial: exactly one authorized Android device is required")
    return available[0]


def reverse_preexists(adb: Path, serial: str, port: int) -> bool:
    mapping = f"tcp:{port}"
    for line in adb_run(adb, serial, "reverse", "--list").splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[-2] == mapping:
            if fields[-1] != mapping:
                raise RuntimeError("Diagnostic reverse port is mapped to another destination; choose a free port")
            return True
    return False


def device_info(adb: Path, serial: str) -> dict:
    return {"serial": serial,
            "model": adb_run(adb, serial, "shell", "getprop", "ro.product.model"),
            "android_version": adb_run(adb, serial, "shell", "getprop", "ro.build.version.release"),
            "android_sdk": adb_run(adb, serial, "shell", "getprop", "ro.build.version.sdk")}


def battery_info(adb: Path, serial: str) -> dict:
    selected = {"level", "temperature", "AC powered", "USB powered", "Wireless powered"}
    values = {}
    for line in adb_run(adb, serial, "shell", "dumpsys", "battery").splitlines():
        if ":" in line:
            key, value = line.strip().split(":", 1)
            if key in selected:
                values[key] = value.strip()
    return values


def capture_phone(adb: Path, serial: str, path: Path) -> tuple[int, int]:
    result = subprocess.run([str(adb), "-s", serial, "exec-out", "screencap", "-p"],
                            capture_output=True, timeout=30,
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    if result.returncode or not result.stdout.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("Android screenshot failed")
    path.write_bytes(result.stdout)
    import struct
    return struct.unpack(">II", result.stdout[16:24])


def stop_collector(process: subprocess.Popen | None) -> None:
    # On a watchdog failure the collector's Python finally cannot run after
    # TerminateProcess. Stop its own ADB logcat descendant as well; the shared
    # ADB daemon was already running before the collector was created.
    if process is not None and process.poll() is None and os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15,
                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    stop_owned(process)


def validate_android_report(report: dict, maps: list[str], runs: int) -> None:
    if not report.get("report_seen") or report.get("errors"):
        raise RuntimeError("Android collector did not see a clean final benchmark report")
    # Reuse the same completeness, actual start-control and Luau checks.
    compatible = dict(report, tag="android-contract", platform="Android", failures=[])
    validate_report(compatible, maps, runs, "android-contract", 0, platform="Android")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / ".codex-tmp/performance/android55.log")
    parser.add_argument("--serial")
    parser.add_argument("--maps", default=",".join(MAPS))
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--port", type=int, default=17860)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--godot", type=Path, default=ROOT / ".codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe")
    parser.add_argument("--server-appdata", type=Path, default=ROOT / ".codex-tmp/performance-server")
    parser.add_argument("--capture-valley", action="store_true", help="Capture the Valley settling window before measured gameplay")
    parser.add_argument("--valley-motion", action="store_true", help="Replay diagnostic movement; these frame measurements are not a baseline")
    parser.add_argument("--joystick", help="Observed screenshot coordinates: start_x,start_y,end_x,end_y")
    parser.add_argument("--camera", help="Observed free camera-area coordinates: start_x,start_y,end_x,end_y")
    parser.add_argument("--valley-start-tap", help="Optional observed original intro-button coordinates: x,y")
    args = parser.parse_args()
    maps = args.maps.split(",")
    if len(set(maps)) != len(maps) or any(key not in MAPS for key in maps):
        parser.error("--maps must contain unique known map names")
    if not 1 <= args.runs <= 5 or not 1024 <= args.port <= 65535 or args.timeout < 30:
        parser.error("Invalid runs/port/timeout")
    joystick = camera_points = start_tap = None
    if args.valley_start_tap:
        if not re.fullmatch(r"\d+,\d+", args.valley_start_tap) or not (args.capture_valley or args.valley_motion):
            parser.error("--valley-start-tap requires observed x,y and a Valley capture/replay")
        start_tap = list(map(int, args.valley_start_tap.split(",")))
    if args.valley_motion:
        if not args.joystick or not re.fullmatch(r"\d+,\d+,\d+,\d+", args.joystick):
            parser.error("--valley-motion requires four observed --joystick coordinates")
        if not args.camera or not re.fullmatch(r"\d+,\d+,\d+,\d+", args.camera):
            parser.error("--valley-motion requires four observed --camera coordinates")
        joystick = list(map(int, args.joystick.split(",")))
        camera_points = list(map(int, args.camera.split(",")))
    apk = isolated_path(args.apk)
    output = isolated_path(args.output)
    server_appdata = isolated_path(args.server_appdata)
    assert_guest_userdata(server_appdata)
    serial = device_serial(ADB, args.serial)
    if not re.fullmatch(r"[A-Za-z0-9_.:-]+", serial):
        raise ValueError("Invalid Android serial")
    identity = {"path": str(apk), "bytes": apk.stat().st_size, "sha256": sha256(apk),
                "package": PACKAGE, "engine_template": "release; isolated diagnostic APK"}
    try:
        with socket.create_connection(("127.0.0.1", args.port), timeout=0.5):
            raise RuntimeError("Private benchmark server port is occupied; no existing process will be stopped")
    except (ConnectionRefusedError, TimeoutError, OSError):
        pass
    previous_reverse = reverse_preexists(ADB, serial, args.port)
    info = device_info(ADB, serial)
    info["battery_before"] = battery_info(ADB, serial)
    cache = prepare_cache(server_appdata, ROOT / ".codex-tmp/android-runner-unused-client", maps, False)
    cache["mode"] = "retained isolated performance-app cache; private server warm"
    cache.pop("copied_only", None)
    output.parent.mkdir(parents=True, exist_ok=True)
    server_log = output.with_suffix(".server.log")
    runner_log = output.with_suffix(".runner.log")
    result_path = output.with_suffix(".json")
    result_path.unlink(missing_ok=True)
    server = collector = None
    movement = camera = recorder = None
    motion_metadata = {}
    video_remote = None
    collector_started = False
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    started = time.monotonic()
    print(f"[android-private] {info['model']} Android {info['android_version']} serial={serial} apk_sha256={identity['sha256']}", flush=True)
    try:
        with server_log.open("w", encoding="utf-8") as server_stream, runner_log.open("w", encoding="utf-8") as collector_stream:
            server = subprocess.Popen([str(args.godot.resolve()), "--headless", "--path", str(ROOT),
                                       "--script", "server/server_main.gd"], cwd=ROOT,
                                      env=guest_environment(server_appdata, args.port), stdout=server_stream,
                                      stderr=subprocess.STDOUT, creationflags=flags)
            wait_server(server, server_log, args.port, min(60, args.timeout))
            env = guest_environment(ROOT / ".codex-tmp/android-runner-host", args.port)
            env["ANDROID_SERIAL"] = serial
            collector = subprocess.Popen([sys.executable, "-X", "utf8", str(ROOT / "tools/run_android_performance.py"),
                                          "--apk", str(apk), "--output", str(output), "--port", str(args.port),
                                          "--timeout", str(args.timeout)], cwd=ROOT, env=env,
                                         stdout=collector_stream, stderr=subprocess.STDOUT, creationflags=flags)
            collector_started = True
            deadline = time.monotonic() + args.timeout + 240
            delivered = set()
            valley_captured = False
            motion_started = None
            walk_started = None
            while collector.poll() is None:
                if server.poll() is not None:
                    raise RuntimeError("Private server exited during Android measurement")
                if time.monotonic() > deadline:
                    raise TimeoutError("Android installation/measurement exceeded its deadline")
                for line in runner_log.read_text(encoding="utf-8", errors="replace").splitlines():
                    if line.startswith("[android]") and line not in delivered:
                        delivered.add(line)
                        print(line, flush=True)
                if (args.capture_valley or args.valley_motion) and not valley_captured and output.exists():
                    if "[perf] START valley " in output.read_text(encoding="utf-8", errors="replace"):
                        valley_captured = True
                        before_path = output.with_suffix(".valley-before.png")
                        width, height = capture_phone(ADB, serial, before_path)
                        motion_metadata = {"before": str(before_path), "dimensions": [width, height],
                                           "inputs": "none; captured before measured sample"}
                        if start_tap:
                            if start_tap[0] >= width or start_tap[1] >= height:
                                raise ValueError("Observed start-button coordinates fall outside the screenshot")
                            adb_run(ADB, serial, "shell", "input", "touchscreen", "tap", *map(str, start_tap))
                            entered_path = output.with_suffix(".valley-entered.png")
                            capture_phone(ADB, serial, entered_path)
                            motion_metadata["start_button_tap"] = start_tap
                            motion_metadata["after_start_tap"] = str(entered_path)
                            print(f"[android-private] Valley original start-button tap: {entered_path}", flush=True)
                        print(f"[android-private] Valley screenshot: {before_path} ({width}x{height})", flush=True)
                        if args.valley_motion:
                            if (max(joystick[0], joystick[2]) >= width or max(joystick[1], joystick[3]) >= height):
                                raise ValueError("Observed joystick coordinates fall outside the current screenshot")
                            if (max(camera_points[0], camera_points[2]) >= width or max(camera_points[1], camera_points[3]) >= height):
                                raise ValueError("Observed camera coordinates fall outside the current screenshot")
                            video_remote = f"/sdcard/bobux-perf-{int(time.time())}.mp4"
                            recorder = subprocess.Popen([str(ADB), "-s", serial, "shell", "screenrecord",
                                                         "--time-limit", "14", "--bit-rate", "4000000", video_remote],
                                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                                        creationflags=flags)
                            camera = subprocess.Popen([str(ADB), "-s", serial, "shell", "input", "touchscreen", "swipe",
                                                       *map(str, camera_points), "2000"], stdout=subprocess.DEVNULL,
                                                      stderr=subprocess.DEVNULL, creationflags=flags)
                            motion_started = time.monotonic()
                            motion_metadata["inputs"] = {"camera_swipe": camera_points, "camera_ms": 2000,
                                                        "joystick_swipe": joystick, "walk_ms": 10000}
                if camera is not None and camera.poll() is not None and walk_started is None:
                    if camera.returncode != 0:
                        raise RuntimeError("Android camera swipe failed")
                    angle_path = output.with_suffix(".valley-angle.png")
                    capture_phone(ADB, serial, angle_path)
                    motion_metadata["after_angle"] = str(angle_path)
                    movement = subprocess.Popen([str(ADB), "-s", serial, "shell", "input", "touchscreen", "swipe",
                                                 *map(str, joystick), "10000"], stdout=subprocess.DEVNULL,
                                                stderr=subprocess.DEVNULL, creationflags=flags)
                    walk_started = time.monotonic()
                    print(f"[android-private] Valley after camera turn: {angle_path}", flush=True)
                if walk_started is not None and "after" not in motion_metadata and time.monotonic() - walk_started >= 10.2:
                    after_path = output.with_suffix(".valley-after.png")
                    capture_phone(ADB, serial, after_path)
                    motion_metadata["after"] = str(after_path)
                    print(f"[android-private] Valley after movement: {after_path}", flush=True)
                if recorder is not None and recorder.poll() is not None and "video" not in motion_metadata:
                    if recorder.returncode != 0:
                        raise RuntimeError("Android Valley screen recording failed")
                    video_path = output.with_suffix(".valley-motion.mp4")
                    adb_run(ADB, serial, "pull", video_remote, str(video_path))
                    motion_metadata["video"] = str(video_path)
                    print(f"[android-private] Valley recording: {video_path}", flush=True)
                time.sleep(1)
            if not result_path.exists():
                raise RuntimeError(f"Android collector produced no report; see {runner_log}")
            report = json.loads(result_path.read_text(encoding="utf-8"))
            shutil_copy = result_path.with_suffix(".collector.json")
            shutil_copy.write_bytes(result_path.read_bytes())
            report["diagnostic_apk"] = identity
            report["device"] = info
            try:
                report["device"]["battery_after"] = battery_info(ADB, serial)
            except (RuntimeError, OSError, subprocess.TimeoutExpired):
                report["device"]["battery_after"] = {"unavailable": True}
            report["private_server"] = {"url": f"ws://127.0.0.1:{args.port}", "live_registry_enabled": False,
                                        "forwarding_preexisting": previous_reverse}
            report["cache"] = cache
            report["collector_exit_code"] = collector.returncode
            report["wall_seconds"] = round(time.monotonic() - started, 3)
            report["measurement_mode"] = "movement diagnostic; not baseline" if args.valley_motion else "no added inputs"
            if motion_metadata:
                report["valley_visual"] = motion_metadata
            client_errors = [line for line in output.read_text(encoding="utf-8", errors="replace").splitlines()
                             if re.search(r"\b(?:SCRIPT )?ERROR:", line) or "ERR_OUT_OF_MEMORY" in line]
            report["client_log_error_count"] = len(client_errors)
            report["client_log_errors"] = client_errors[:20]
            errors = [line for line in server_log.read_text(encoding="utf-8", errors="replace").splitlines()
                      if "SCRIPT ERROR:" in line or line.startswith("ERROR:")]
            report["server_log_error_count"] = len(errors)
            report["server_log_errors"] = errors[:20]
            result_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
            validate_android_report(report, maps, args.runs)
            if args.valley_motion and not all(key in motion_metadata for key in ("before", "after_angle", "after", "video")):
                raise RuntimeError("Valley movement replay did not capture all visual evidence")
            if collector.returncode or errors or client_errors:
                raise RuntimeError(f"Android collector/server failed; see {runner_log} and {server_log}")
            print(f"[android-private] PASS {len(report['results'])} map runs; {result_path}", flush=True)
            return 0
    finally:
        stop_owned(movement)
        stop_owned(camera)
        stop_owned(recorder)
        stop_collector(collector)
        stop_owned(server)
        if collector_started:
            try:
                adb_run(ADB, serial, "shell", "am", "force-stop", PACKAGE)
                if not previous_reverse:
                    adb_run(ADB, serial, "reverse", "--remove", f"tcp:{args.port}")
                if video_remote is not None:
                    adb_run(ADB, serial, "shell", "rm", video_remote)
            except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
                print(f"[android-private] Diagnostic cleanup unavailable: {error}", file=sys.stderr)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, TimeoutError, OSError, json.JSONDecodeError, subprocess.TimeoutExpired) as error:
        print(f"[android-private] FAIL: {error}", file=sys.stderr, flush=True)
        raise SystemExit(1)
