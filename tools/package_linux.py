#!/usr/bin/env python3
"""Package a Linux export, preserving executable modes even on Windows builders."""
import argparse
import hashlib
import json
import shutil
import tarfile
import urllib.request
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', type=int, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    stage = args.stage.resolve()
    assert stage.is_relative_to(root / 'dist'), 'Stage must be inside dist'
    binary = stage / 'Bobux.x86_64'
    assert binary.read_bytes()[:5] == b'\x7fELF\x02', 'Expected a 64-bit ELF executable'
    assert list(stage.rglob('*luaapi*release*x86_64.so')), 'Linux Lua native library missing'
    converter = stage / 'addons/rbxl_importer/rbxl_converter.py'
    converter.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / 'addons/rbxl_importer/rbxl_converter.py', converter)
    shutil.copyfile(root / 'assets/branding/bobux_logo_ui.png', stage / 'bobux.png')
    runtime = root / 'dist/release/appimage-runtime-x86_64'
    runtime_hash = '1cc49bcf1e2ccd593c379adb17c9f85a36d619088296504de95b1d06215aebbf'
    if not runtime.exists():
        urllib.request.urlretrieve('https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64', runtime)
    assert hashlib.sha256(runtime.read_bytes()).hexdigest() == runtime_hash, 'AppImage runtime checksum mismatch'
    (stage / 'AppRun').write_text("""#!/bin/sh
set -eu
cd -- "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# Respect explicit/headless arguments; otherwise prefer the active Wayland session.
case " $* " in *' --headless '*|*' --display-driver '*) exec ./Bobux.x86_64 "$@";; esac
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    exec ./Bobux.x86_64 --display-driver "${BOBUX_DISPLAY_DRIVER:-wayland}" "$@"
fi
exec ./Bobux.x86_64 "$@"
""", encoding='utf-8', newline='\n')
    (stage / 'bobux.desktop').write_text('[Desktop Entry]\nType=Application\nName=Bobux\nExec=AppRun\nIcon=bobux\nCategories=Game;\nTerminal=false\n', encoding='utf-8', newline='\n')
    (stage / 'Bobux.sh').write_text('''#!/bin/sh
set -eu
cd -- "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec ./Bobux.x86_64 "$@"
''', encoding='utf-8', newline='\n')
    (stage / 'install.sh').write_text('''#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
destination="$HOME/.local/share/bobux"
mkdir -p "$destination" "$HOME/.local/share/applications"
if [ "$source_dir" != "$destination" ]; then cp -R "$source_dir/." "$destination/"; fi
chmod +x "$destination/Bobux.sh" "$destination/Bobux.x86_64"
# Desktop entries escape reserved characters; quotes protect spaces in HOME.
escaped=$(printf '%s' "$destination" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g; s/`/\\\\`/g; s/\\$/\\\\$/g; s/%/%%/g')
cat > "$HOME/.local/share/applications/bobux.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Bobux
Comment=Play and create in Bobux
Exec="$escaped/Bobux.sh"
Icon=$destination/bobux.png
Terminal=false
Categories=Game;
EOF
printf '%s\\n' 'Bobux installed. Open Bobux from your applications menu.'
''', encoding='utf-8', newline='\n')
    (stage / 'README.txt').write_text('Bobux Linux x86_64\n\nRun: sh Bobux.sh\nInstall menu shortcut: sh install.sh\nRequires OpenGL 3.3 and Python 3 for importing RBXL files.\nUpdates: download the new archive from the Bobux website.\nPlayer data remains in the Godot application data directory.\n', encoding='utf-8', newline='\n')
    out = root / 'dist/release'
    archive = out / 'Bobux-Linux-x86_64.tar.gz'
    def mode(info):
        info.uid = info.gid = 0
        info.uname = info.gname = ''
        info.mode = 0o755 if info.isdir() or (info.name.endswith(('.sh', '.x86_64', '.so')) or info.name.endswith('/AppRun')) else 0o644
        return info
    with tarfile.open(archive, 'w:gz') as tar:
        tar.add(stage, arcname='Bobux', filter=mode)
        tar.add(runtime, arcname='appimage-runtime-x86_64', filter=mode)
        tar.add(root / 'tools/build_appimage.py', arcname='build_appimage.py', filter=mode)
    manifest = {'version': args.version, 'build': args.build, 'platforms': {}}
    for platform, filename in [('windows', 'BobuxSetup.exe'), ('linux', archive.name)]:
        path = out / filename
        assert path.stat().st_size > 1024 * 1024
        if platform == 'windows':
            with path.open('rb') as file: assert file.read(2) == b'MZ', 'Invalid Setup executable'
        manifest['platforms'][platform] = {'url': '/downloads/' + filename, 'sha256': hashlib.file_digest(path.open('rb'), 'sha256').hexdigest(), 'size': path.stat().st_size}
    (out / 'desktop-latest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8', newline='\n')
    print('Windows Setup and Linux packages validated:', args.version, args.build)

if __name__ == '__main__':
    main()
