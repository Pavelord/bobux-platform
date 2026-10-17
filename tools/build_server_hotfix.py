"""Package runtime resources only; never include account caches or API secrets."""
from pathlib import Path
import tarfile, hashlib, re

root = Path(__file__).resolve().parents[1]
server_luau_libraries = {
    'addons/luaAPI/bin/libbobuxluau.linux.template_debug.x86_64.so',
    'addons/luaAPI/bin/libbobuxluau.linux.template_release.x86_64.so',
}
folders = ['scripts', 'autoload', 'scenes', 'addons', 'assets', 'files', 'images',
           'maps', 'obby1', 'obby2', 'script_templates', 'text_editor_themes',
           'Roblox-Materials/ClassicSurfaceTypes', 'toolbox_assets/metadata']
files = {root / 'project.godot', root / 'icon.svg', root / 'icon.ico', root / 'server/server_main.gd'}
for folder in folders:
    files.update(p for p in (root / folder).rglob('*') if p.is_file() and not p.is_symlink())
for path in (root / 'tools').rglob('*.gd'):
    if path.name.startswith('validate_') or path.parent.name == 'fixtures': files.add(path)
archive = root / '.codex-tmp/server-network-hotfix.tar.gz'
imported = set()
for file in files:
    if file.suffix == '.import':
        imported.update(root / target.removeprefix('res://') for target in re.findall(r'"(res://\.godot/imported/[^"\n]+)"', file.read_text(encoding='utf-8')))
imported.update(root / '.godot' / name for name in ['global_script_class_cache.cfg', 'extension_list.cfg'])
with tarfile.open(archive, 'w:gz', compresslevel=6) as out:
    for file in sorted(files):
        relative = file.relative_to(root).as_posix()
        if not file.is_file() or any(x in file.parts for x in ['.git', '.godot', '__pycache__']): continue
        if file.suffix in ['.dll', '.pdb', '.lib', '.exp', '.map', '.dylib', '.pyc']: continue
        if '/bin/' in relative and relative not in server_luau_libraries: continue
        out.add(file, arcname=relative, recursive=False)
    for file in sorted(imported):
        if file.is_file(): out.add(file, arcname=file.relative_to(root).as_posix(), recursive=False)
print(archive, archive.stat().st_size, hashlib.sha256(archive.read_bytes()).hexdigest())
