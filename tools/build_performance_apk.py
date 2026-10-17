"""Build an isolated Android benchmark; restore export presets after exporting."""
import argparse
import hashlib
import pathlib
import re
import subprocess
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("--godot", required=True)
parser.add_argument("--output", required=True)
parser.add_argument("--maps", default="park,valley,nds")
parser.add_argument("--seconds", type=int, default=30)
parser.add_argument("--runs", type=int, default=2)
parser.add_argument("--tag", default="android")
parser.add_argument("--renderer", choices=["gl_compatibility", "mobile"])
parser.add_argument("--bottlenecks", action="store_true")
parser.add_argument("--native-profile", action="store_true")
parser.add_argument("--loading-no-3d", action="store_true")
parser.add_argument("--batch-static", action="store_true")
parser.add_argument("--batch-ab", action="store_true")
parser.add_argument("--release", action="store_true", help="Use the shipping engine template, signed with the local test key")
parser.add_argument("--test-keystore", help="Local Android debug keystore for release-template benchmarks")
parser.add_argument("--server", default="ws://109.71.245.162/ws")
args = parser.parse_args()
if not re.fullmatch(r"[a-z0-9,_-]+", args.maps + args.tag):
    parser.error("maps and tag must contain only safe benchmark identifiers")
if not re.fullmatch(r"wss?://[a-zA-Z0-9./:_-]+", args.server):
    parser.error("server must be a WebSocket URL without credentials")
root = pathlib.Path(__file__).resolve().parents[1]
presets = root / "export_presets.cfg"
original = presets.read_bytes()
project = root / "project.godot"
original_project = project.read_bytes()
extension = root / "addons/luaAPI/luaAPI.gdextension"
original_extension = extension.read_bytes()
source = original.decode("utf-8-sig")
match = re.search(r'\[preset\.(\d+)\]\s+name="Android".*?(?=\n\[preset\.\d+\]|\Z)', source, re.S)
if not match:
    raise SystemExit("Android preset missing")
next_index = max(map(int, re.findall(r"\[preset\.(\d+)\]", source))) + 1
test_preset = re.sub(r"\[preset\.\d+", f"[preset.{next_index}", match.group())
def setting(key, value):
    global test_preset
    test_preset, count = re.subn(r"^" + re.escape(key) + r"=.*$", key + "=" + value, test_preset, flags=re.M)
    if count != 1:
        raise SystemExit(f"Expected one {key}, got {count}")
setting("name", '"Android Performance"')
setting("package/unique_name", '"com.bobux.performance"')
setting("package/name", '"Bobux Performance"')
setting("version/code", "1")
setting("version/name", '"performance-local"')
setting("architectures/armeabi-v7a", "false")
if args.release:
    if not args.test_keystore or not pathlib.Path(args.test_keystore).is_file():
        parser.error("--release requires an existing --test-keystore")
    setting("keystore/release", '"' + pathlib.Path(args.test_keystore).resolve().as_posix() + '"')
    setting("keystore/release_user", '"androiddebugkey"')
    setting("keystore/release_password", '"android"')
flags = (" --bottlenecks" if args.bottlenecks else "") + (" --profile-lua-native" if args.native_profile else "") + (" --loading-no-3d" if args.loading_no_3d else "")
flags += " --batch-static" if args.batch_static else ""
flags += " --batch-ab" if args.batch_ab else ""
setting("command_line/extra_args", '"-- --maps=%s --seconds=%d --runs=%d --tag=%s --server=%s --profile-loading%s"' % (args.maps, args.seconds, args.runs, args.tag, args.server, flags))
output = pathlib.Path(args.output).resolve()
output.parent.mkdir(parents=True, exist_ok=True)
try:
    presets.write_text(source + "\n" + test_preset + "\n", encoding="utf-8")
    test_project = re.sub(r'^run/main_scene=.*$', 'run/main_scene="res://scripts/diagnostics/runtime_performance_probe.tscn"', original_project.decode("utf-8-sig"), flags=re.M)
    if args.renderer:
        test_project = re.sub(r'^renderer/rendering_method.mobile=.*$', 'renderer/rendering_method.mobile="%s"' % args.renderer, test_project, flags=re.M)
    project.write_text(test_project, encoding="utf-8")
    # Use the production VM in the debuggable APK. The existing debug mappings
    # select Lua 5.4, which cannot benchmark the shipping Luau scheduler.
    extension.write_text(original_extension.decode().replace('android.debug.arm64 = "bin/libluaapi.android.template_debug.arm64.so"', 'android.debug.arm64 = "bin/libbobuxluau.android.template_release.arm64.so"'), encoding="utf-8")
    result = subprocess.run([str(pathlib.Path(args.godot).resolve()), "--headless", "--path", str(root), "--export-release" if args.release else "--export-debug", "Android Performance", str(output)], cwd=root)
    if result.returncode:
        raise SystemExit(result.returncode)
    # A native linker can temporarily truncate an SO. Never install an APK
    # that captured that intermediate file or a different runtime revision.
    library = root / "addons/luaAPI/bin/libbobuxluau.android.template_release.arm64.so"
    with zipfile.ZipFile(output) as archive:
        embedded = archive.read("lib/arm64-v8a/" + library.name)
    if len(embedded) < 100_000 or hashlib.sha256(embedded).digest() != hashlib.sha256(library.read_bytes()).digest():
        raise SystemExit("Benchmark APK native Luau library is missing, truncated or stale")
finally:
    presets.write_bytes(original)
    project.write_bytes(original_project)
    extension.write_bytes(original_extension)
