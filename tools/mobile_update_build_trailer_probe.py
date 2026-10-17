"""Build an isolated release-template APK for the real Android trailer decoder."""
from pathlib import Path
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / ".codex-tmp/mobile_update_trailer_probe"
GODOT = ROOT / ".codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe"
PROBE.mkdir(parents=True, exist_ok=True)
(PROBE / ".gdignore").touch()
(PROBE / "assets/video").mkdir(parents=True, exist_ok=True)
shutil.copy2(ROOT / "autoload/update_trailer.gd", PROBE / "update_trailer.gd")
shutil.copy2(ROOT / "assets/video/bobux_halloween_2026.ogv", PROBE / "assets/video/bobux_halloween_2026.ogv")
(PROBE / "user_session.gd").write_text('extends Node\nvar user_id := "android-trailer-qa-fixture"\n', encoding="utf-8")
(PROBE / "project.godot").write_text('''config_version=5
[application]
config/name="Bobux Trailer QA"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
boot_splash/bg_color=Color(0,0,0,1)
boot_splash/show_image=false
[autoload]
UserSession="*res://user_session.gd"
UpdateTrailer="*res://update_trailer.gd"
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=0
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true
''', encoding="utf-8")
(PROBE / "main.tscn").write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://main.gd" id="1"]
[node name="ProbeBootstrap" type="Node"]
script = ExtResource("1")
''', encoding="utf-8")
source = (ROOT / "export_presets.cfg").read_text(encoding="utf-8-sig")
match = re.search(r'\[preset\.(\d+)\]\s+name="Android".*?(?=\n\[preset\.\d+\]|\Z)', source, re.S)
if match is None:
    raise SystemExit("Android export preset missing")
text = re.sub(r'\[preset\.\d+', '[preset.0', match.group())
settings = {
    "name": '"Android Trailer QA"',
    "include_filter": '""',
    "exclude_filter": '"*.py,*.md,*.log,*.json"',
    "export_path": '"Bobux-Trailer-QA.apk"',
    "architectures/armeabi-v7a": "false",
    "version/code": "1",
    "version/name": '"trailer-qa-local"',
    "package/unique_name": '"com.bobux.trailerqa"',
    "package/name": '"Bobux Trailer QA"',
    "keystore/release": json.dumps((ROOT / "tools/mobile/bobux_debug.keystore").as_posix()),
    "keystore/release_user": '"bobuxdebug"',
    "keystore/release_password": '"android"',
    "launcher_icons/main_192x192": '""',
    "launcher_icons/adaptive_foreground_432x432": '""',
    "launcher_icons/adaptive_background_432x432": '""',
}
for key, value in settings.items():
    text, count = re.subn(r'^' + re.escape(key) + r'=.*$', key + '=' + value, text, flags=re.M)
    if count != 1:
        raise SystemExit(f"Expected one preset key {key}, got {count}")
(PROBE / "export_presets.cfg").write_text(text, encoding="utf-8")
for arguments in (["--editor", "--import"], ["--export-release", "Android Trailer QA", str(PROBE / "Bobux-Trailer-QA.apk")]):
    subprocess.run([str(GODOT), "--headless", "--path", str(PROBE), *arguments], check=True, cwd=PROBE)
print("TRAILER_QA_APK=" + str(PROBE / "Bobux-Trailer-QA.apk"))
