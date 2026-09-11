"""Build a static, versioned Toolbox release; no API restart or client build needed."""
from __future__ import annotations
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import struct
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def resource_files(entry):
    primary = ROOT / entry['file'].removeprefix('res://')
    files = {primary.name: primary}
    if entry['type'] == 'model':
        blob = primary.read_bytes()
        length = struct.unpack_from('<I', blob, 12)[0]
        gltf = json.loads(blob[20:20 + length])
        for record in gltf.get('images', []) + gltf.get('buffers', []):
            uri = record.get('uri', '')
            if not uri or uri.startswith('data:'): continue
            relative = PurePosixPath(uri)
            if relative.is_absolute() or '..' in relative.parts or ':' in uri:
                raise ValueError('Unsafe model dependency: ' + uri)
            files[uri] = primary.parent.joinpath(*relative.parts)
    return primary.name, files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', default='http://109.71.245.162/toolbox')
    parser.add_argument('--output', type=Path, default=ROOT / '.codex-tmp/toolbox-server-release')
    args = parser.parse_args()
    source = json.loads((ROOT / 'toolbox_assets/metadata/index.json').read_text(encoding='utf-8'))
    output = args.output
    (output / 'packages').mkdir(parents=True, exist_ok=True)
    (output / 'thumbnails').mkdir(exist_ok=True)
    (output / 'licenses').mkdir(exist_ok=True)
    entries = []
    for raw in source['assets']:
        if raw.get('license') != 'CC0' or not raw.get('validated'): raise ValueError('Unverified source ' + raw['id'])
        entry = dict(raw)
        entrypoint, files = resource_files(entry)
        buffer = io.BytesIO()
        file_rows = []
        with zipfile.ZipFile(buffer, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for name, path in sorted(files.items()):
                data = path.read_bytes()
                info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, data)
                file_rows.append({'path': name, 'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)})
        data = buffer.getvalue()
        digest = hashlib.sha256(data).hexdigest()
        (output / 'packages' / (digest + '.zip')).write_bytes(data)
        entry.update(package_sha256=digest, package_bytes=len(data), entrypoint=entrypoint, package_files=file_rows)
        if entry.get('thumbnail'):
            image = (ROOT / entry['thumbnail'].removeprefix('res://')).read_bytes()
            image_hash = hashlib.sha256(image).hexdigest()
            (output / 'thumbnails' / (image_hash + '.png')).write_bytes(image)
            entry['thumbnail_sha256'] = image_hash
        license_path = ROOT / entry['license_file'].removeprefix('res://')
        (output / 'licenses' / license_path.name).write_bytes(license_path.read_bytes())
        entries.append(entry)
    revision = hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()[:16]
    for entry in entries:
        prefix = args.base_url.rstrip('/') + '/' + revision
        entry['asset_url'] = prefix + '/packages/' + entry['package_sha256'] + '.zip'
        entry['thumbnail_url'] = prefix + '/thumbnails/' + entry['thumbnail_sha256'] + '.png' if entry.get('thumbnail_sha256') else ''
        entry['distributed_license_url'] = prefix + '/licenses/' + Path(entry['license_file']).name
    index = {'version': 2, 'revision': revision, 'assets': entries}
    (output / 'index.json').write_text(json.dumps(index, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    bundle = output.parent / ('toolbox-' + revision + '.tar')
    with tarfile.open(bundle, 'w') as archive:
        for path in sorted(output.rglob('*')):
            if path.is_file(): archive.add(path, arcname=revision + '/' + path.relative_to(output).as_posix())
    print(json.dumps({'revision': revision, 'assets': len(entries), 'archive': str(bundle), 'bytes': bundle.stat().st_size}))


if __name__ == '__main__': main()
