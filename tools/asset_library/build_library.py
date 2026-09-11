"""Build the redistributable CC0 Toolbox library from verified official packs.

Archives stay outside res://. Re-running reuses downloads and content hashes.
Godot's finalize_library.gd validates actual resources and renders thumbnails.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import subprocess
import time
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'toolbox_assets'
CACHE = Path(os.environ.get('LOCALAPPDATA', Path.home() / '.cache')) / 'Bobux' / 'asset-library-cache'
PACKS = {
    'blocky-characters': ('model', 'Characters'),
    'furniture-kit': ('model', 'Furniture'), 'nature-kit': ('model', 'Nature'),
    'car-kit': ('model', 'Vehicles'), 'city-kit-suburban': ('model', 'Buildings'),
    'city-kit-commercial': ('model', 'Buildings'), 'city-kit-roads': ('model', 'Roads'),
    'fantasy-town-kit': ('model', 'Fantasy'), 'castle-kit': ('model', 'Fantasy'),
    'space-station-kit': ('model', 'Sci Fi'), 'survival-kit': ('model', 'Props'),
    'food-kit': ('model', 'Food'), 'blaster-kit': ('model', 'Weapons'),
    'pirate-kit': ('model', 'Fantasy'), 'platformer-kit': ('model', 'Prototype'),
    'interface-sounds': ('sound', 'UI'), 'impact-sounds': ('sound', 'Impacts'),
    'rpg-audio': ('sound', 'RPG'), 'sci-fi-sounds': ('sound', 'Sci Fi'),
    'ui-audio': ('sound', 'UI'), 'digital-audio': ('sound', 'UI'),
}
# Keywords are relationships, not hard-coded request-to-file choices.
CONCEPTS = {
    'character': ['npc', 'humanoid', 'person', 'персонаж', 'нпс', 'человек'],
    'house': ['home', 'building', 'residential', 'дом', 'домик', 'village', 'деревня'],
    'tree': ['forest', 'woodland', 'foliage', 'nature', 'дерево', 'деревья', 'лес'],
    'rock': ['stone', 'nature', 'forest', 'камень', 'скала'],
    'chair': ['seat', 'furniture', 'office', 'interior', 'стул', 'офис'],
    'desk': ['table', 'office', 'furniture', 'стол', 'офис'],
    'table': ['desk', 'furniture', 'interior', 'стол'],
    'car': ['vehicle', 'road', 'traffic', 'автомобиль', 'машина'],
    'road': ['street', 'city', 'traffic', 'дорога', 'улица'],
    'blaster': ['weapon', 'gun', 'pistol', 'handgun', 'combat', 'пистолет', 'оружие'],
    'laser': ['blaster', 'weapon', 'gunshot', 'shooting', 'sci-fi', 'выстрел', 'лазер'],
    'explosion': ['blast', 'rocket', 'combat', 'взрыв', 'рпг'],
    'door': ['house', 'open', 'close', 'дверь'],
    'footstep': ['walking', 'character', 'шаги'],
    'click': ['button', 'interface', 'ui', 'кнопка', 'интерфейс'],
    'impact': ['hit', 'collision', 'удар'],
    'wood': ['wooden', 'дерево', 'деревянный'],
    'wall': ['room', 'building', 'architecture', 'стена', 'комната'],
    'floor': ['room', 'building', 'пол', 'комната'],
    'window': ['house', 'building', 'окно'],
    'castle': ['medieval', 'village', 'fantasy', 'замок', 'средневековый'],
}

def fetch(url: str, destination: Path) -> None:
    origin = destination.with_suffix(destination.suffix + '.url')
    if destination.exists() and destination.stat().st_size > 0 and origin.exists() and origin.read_text(encoding='utf-8') == url:
        return
    partial = destination.with_suffix(destination.suffix + '.part')
    if not origin.exists() or origin.read_text(encoding='utf-8') != url:
        # Never resume bytes from a different source version.
        partial.unlink(missing_ok=True)
    origin.write_text(url, encoding='utf-8')
    offset = partial.stat().st_size if partial.exists() else 0
    request = urllib.request.Request(url, headers={'User-Agent': 'Bobux-CC0-Library/1.0', **({'Range': f'bytes={offset}-'} if offset else {})})
    with urllib.request.urlopen(request, timeout=45) as response:
        mode = 'ab' if offset and response.status == 206 else 'wb'
        with partial.open(mode) as output:
            while block := response.read(1024 * 1024):
                output.write(block)
    partial.replace(destination)

def human_name(stem: str) -> str:
    stem = re.sub(r'([a-z])([A-Z])', r'\1 \2', stem)
    stem = re.sub(r'([a-zA-Z])(\d)', r'\1 \2', stem)
    stem = re.sub(r'[_\-]+', ' ', stem)
    return ' '.join(stem.split()).title()

def semantic_metadata(stem: str, slug: str, category: str, kind: str) -> dict:
    name = human_name(stem)
    if slug == 'city-kit-suburban' and name.startswith('Building Type '): name = name.replace('Building Type ', 'Suburban House ')
    elif slug == 'city-kit-commercial' and 'Building' in name: name = 'City ' + name
    elif slug == 'car-kit' and name in ['Sedan', 'Sedan Sports', 'Hatchback Sports', 'Suv', 'Suv Luxury']:
        name += ' Car'
    words = re.findall(r'[^\W_]+', name.lower())
    tags = set(words + category.lower().split() + [kind])
    synonyms, use_cases = set(), set()
    for concept, related in CONCEPTS.items():
        if concept in words or concept + 's' in words:
            tags.add(concept)
            use_cases.update(related)
            synonyms.update(x for x in related if re.search('[а-яё]', x))
    role = 'prop' if kind == 'model' else 'sound'
    if 'house' in words or 'building' in words:
        role = 'building'
        synonyms.update(['house', 'home', 'building', 'дом', 'здание'])
        tags.update(['residential'] if slug == 'city-kit-suburban' else ['city'])
    elif 'tree' in words and not set(words) & {'log','trunk'}:
        role = 'tree'
        synonyms.update(['forest', 'foliage', 'дерево', 'лес'])
    elif slug == 'car-kit' and not set(words) & {'debris','wheel','box','cone'}:
        role = 'vehicle'
        synonyms.update(['car', 'vehicle', 'автомобиль', 'машина'])
    elif 'blaster' in words:
        role = 'weapon'
        synonyms.update(['pistol', 'gun', 'handgun', 'пистолет', 'оружие'])
    elif kind == 'sound' and 'laser' in words:
        synonyms.update(['gunshot', 'blaster', 'shooting', 'выстрел'])
    if kind == 'model' and set(words) & {'wall','floor','roof','window','balcony','debris','wheel','chimney','pillar','door','fence','rail','pipe','tower','sign'}:
        role = 'component'
    if slug in ['fantasy-town-kit','castle-kit']:
        use_cases.update(['medieval','village','fantasy','средневековый','деревня'])
    if kind == 'model' and category == 'Roads' and 'road' in words and 'sign' not in words:
        synonyms.update(['street','city street','дорога','улица'])
    return {'name': name, 'role': role, 'tags': sorted(tags), 'synonyms': sorted(synonyms), 'ai_use_cases': sorted(tags | use_cases | synonyms)}

def glb_metadata(data: bytes) -> dict:
    magic, version, length = struct.unpack_from('<III', data)
    if magic != 0x46546C67 or version != 2 or length != len(data):
        raise ValueError('Invalid GLB header')
    size, kind = struct.unpack_from('<II', data, 12)
    if kind != 0x4E4F534A: raise ValueError('Missing GLB JSON chunk')
    gltf = json.loads(data[20:20+size])
    for resource in gltf.get('buffers', []) + gltf.get('images', []):
        if resource.get('uri', '').startswith(('http:', 'https:')):
            raise ValueError('External network dependency in GLB')
    return gltf

def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
    temporary.replace(path)

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packs', nargs='*', default=list(PACKS))
    parser.add_argument('--prepare-only', action='store_true', help='Download/index candidates without invoking Godot validation')
    parser.add_argument('--godot', default=shutil.which('godot') or str(ROOT / '.codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'))
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    metadata_dir = DEST / 'metadata'
    metadata_dir.mkdir(parents=True, exist_ok=True)
    previous_path = metadata_dir / 'candidates.json'
    previous = json.loads(previous_path.read_text(encoding='utf-8')) if previous_path.exists() else {'assets': []}
    entries = {entry['id']: entry for entry in previous['assets']}
    for entry in entries.values():
        if entry['source'] == 'Kenney':
            entry.update(semantic_metadata(PurePosixPath(entry['original_filename']).stem, entry['source_url'].rsplit('/', 1)[-1], entry['category'], entry['type']))
    hashes = {entry['sha256']: entry['file'] for entry in entries.values()}
    report_path = metadata_dir / 'asset_import_report.json'
    prior_report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {}
    attempted_sources = {'https://kenney.nl/assets/' + slug for slug in args.packs}
    def retained_log(name):
        path = metadata_dir / name
        rows = json.loads(path.read_text(encoding='utf-8')) if path.exists() else []
        return [row for row in rows if row.get('source') not in attempted_sources]
    skipped, failed, packs = retained_log('skipped_assets.json'), retained_log('failed_downloads.json'), []
    duplicates = downloaded = 0
    for slug in args.packs:
        if slug not in PACKS:
            skipped.append({'source': slug, 'reason': 'Source not in verified allowlist'})
            continue
        source_url = 'https://kenney.nl/assets/' + slug
        try:
            # Check the current official page, not an unrelated page mentioning CC0.
            with urllib.request.urlopen(source_url, timeout=30) as response:
                html = response.read().decode('utf-8')
            if not re.search(r'creativecommons\.org/(?:publicdomain/zero/1\.0|publicdomain/zero)', html):
                skipped.append({'source': source_url, 'reason': 'Official page does not confirm CC0'})
                continue
            urls = re.findall(r'href=["\'](https://kenney\.nl/[^"\']+\.zip)["\']', html)
            if not urls: raise ValueError('Official download URL missing')
            archive = CACHE / (slug + '.zip')
            if not archive.exists(): downloaded += 1
            fetch(urls[0], archive)
            with zipfile.ZipFile(archive) as pack:
                licenses = [p for p in pack.namelist() if PurePosixPath(p).name.lower() in ('license.txt', 'licence.txt')]
                license_text = '\n'.join(pack.read(p).decode('utf-8', errors='replace') for p in licenses)
                if not re.search(r'CC0|publicdomain/zero', license_text) or re.search(r'CC[ -]?BY|Attribution(?:-|\s)+(?:NonCommercial|ShareAlike|3\.0|4\.0)|\bGPL\b', license_text, re.I):
                    skipped.append({'source': source_url, 'reason': 'Archive license missing or not CC0'})
                    continue
                (metadata_dir / 'licenses').mkdir(exist_ok=True)
                license_file = metadata_dir / 'licenses' / (slug + '.txt')
                license_file.write_text(license_text, encoding='utf-8')
                kind, category = PACKS[slug]
                selected = [p for p in pack.namelist() if p.lower().endswith('.glb' if kind == 'model' else '.ogg') and PurePosixPath(p).name.lower() != 'preview.ogg']
                if not selected: raise ValueError('No supported GLB/OGG runtime assets in pack')
                pack_ids = set()
                for member in selected:
                    try:
                        original = PurePosixPath(member)
                        if '..' in original.parts or original.is_absolute(): raise ValueError('Unsafe archive path')
                        data = pack.read(member)
                        if not data: raise ValueError('Empty asset')
                        gltf = glb_metadata(data) if kind == 'model' else {}
                        digest = hashlib.sha256(data).hexdigest()
                        stem = original.stem
                        asset_id = 'kenney_' + slug.replace('-', '_') + '_' + re.sub('[^a-z0-9]+', '_', stem.lower())
                        if asset_id in pack_ids: raise ValueError('Duplicate normalized source asset ID')
                        pack_ids.add(asset_id)
                        semantic = semantic_metadata(stem, slug, category, kind)
                        name = semantic['name']
                        local = DEST / ('models' if kind == 'model' else 'sounds') / slug / original.name
                        if digest in hashes and hashes[digest] != 'res://' + local.relative_to(ROOT).as_posix():
                            file_path = hashes[digest]
                            duplicates += 1
                        else:
                            local.parent.mkdir(parents=True, exist_ok=True)
                            if not local.exists() or hashlib.sha256(local.read_bytes()).hexdigest() != digest: local.write_bytes(data)
                            file_path = 'res://' + local.relative_to(ROOT).as_posix()
                            hashes[digest] = file_path
                        # GLB can still reference a shared palette. Preserve relative dependencies.
                        for image in gltf.get('images', []) + gltf.get('buffers', []):
                            uri = image.get('uri', '')
                            if not uri or uri.startswith('data:'): continue
                            relative = PurePosixPath(uri)
                            if '..' in relative.parts or relative.is_absolute(): raise ValueError('Unsafe texture URI')
                            texture = local.parent.joinpath(*relative.parts)
                            texture.parent.mkdir(parents=True, exist_ok=True)
                            texture.write_bytes(pack.read(str(original.parent / relative)))
                        entries[asset_id] = {
                            'id': asset_id, 'name': name, 'type': kind, 'category': category,
                            **semantic,
                            'description': f'{name}. {category} asset from Kenney {human_name(slug)}.',
                            'source': 'Kenney', 'source_url': source_url, 'download_url': urls[0],
                            'source_asset_id': f'{slug}/{member}', 'original_filename': member,
                            'license': 'CC0', 'license_url': 'https://creativecommons.org/publicdomain/zero/1.0/',
                            'license_file': 'res://' + license_file.relative_to(ROOT).as_posix(),
                            'file': file_path, 'format': original.suffix[1:], 'sha256': digest,
                            'thumbnail': f'res://toolbox_assets/thumbnails/{asset_id}.png' if kind == 'model' else '',
                            'animations': len(gltf.get('animations', [])),
                            'size_bytes': len(data),
                        }
                    except Exception as exc:
                        failed.append({'source': source_url, 'file': member, 'error': str(exc)})
                packs.append({'pack': slug, 'assets': len(pack_ids), 'archive_bytes': archive.stat().st_size, 'license': 'CC0'})
                print(json.dumps(packs[-1]), flush=True)
        except Exception as exc:
            failed.append({'source': source_url, 'error': str(exc)})
            print(json.dumps(failed[-1]), flush=True)
        write_json(previous_path, {'version': 1, 'assets': sorted(entries.values(), key=lambda x: x['id'])})
    write_json(metadata_dir / 'skipped_assets.json', skipped)
    write_json(metadata_dir / 'failed_downloads.json', failed)
    write_json(previous_path, {'version': 1, 'assets': sorted(entries.values(), key=lambda x: x['id'])})
    all_packs = {row['pack']: row for row in prior_report.get('packs', [])}
    all_packs.update({row['pack']: row for row in packs})
    for entry in entries.values():
        slug = entry['source_url'].rsplit('/', 1)[-1]
        all_packs.setdefault(slug, {'pack': slug, 'license': entry['license']})
    for slug, row in all_packs.items():
        row['assets'] = sum(entry['source_url'].endswith('/' + slug) for entry in entries.values())
    required = ['id', 'name', 'type', 'category', 'tags', 'source_url', 'license', 'license_file', 'file', 'sha256']
    report = {'downloaded_this_run': downloaded, 'candidates': len(entries), 'models': sum(x['type'] == 'model' for x in entries.values()), 'sounds': sum(x['type'] == 'sound' for x in entries.values()), 'duplicates': len(entries) - len({x['file'] for x in entries.values()}), 'failed': len(failed), 'skipped': len(skipped), 'skipped_due_to_license': sum('license' in str(x.get('reason', '')).lower() for x in skipped), 'missing_metadata': sum(any(not x.get(key) for key in required) for x in entries.values()), 'packs': sorted(all_packs.values(), key=lambda x: x['pack'])}
    write_json(report_path, report)
    print(json.dumps(report), flush=True)
    if not args.prepare_only:
        if not Path(args.godot).is_file():
            parser.error('Godot not found. Pass --godot PATH or use --prepare-only.')
        # A real rendering driver is required for thumbnails. No editor import
        # is needed: the validator also supports loading raw GLB/OGG files.
        run = subprocess.run([args.godot, '--path', str(ROOT), '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--resolution', '320x240', '--script', 'tools/asset_library/finalize_library.gd'], cwd=ROOT)
        if run.returncode: return run.returncode
    return 0 if not failed else 1

if __name__ == '__main__':
    raise SystemExit(main())
