"""Verify the actual Windows EXE icon resources against the release ICO."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct


def icon_images(path: Path) -> list[bytes]:
    data = path.read_bytes()
    reserved, kind, count = struct.unpack_from("<HHH", data)
    if reserved or kind != 1 or not count:
        raise ValueError("Invalid ICO directory")
    images = []
    for index in range(count):
        size, offset = struct.unpack_from("<II", data, 6 + index * 16 + 8)
        if offset + size > len(data):
            raise ValueError("Truncated ICO image")
        images.append(data[offset:offset + size])
    return images


def executable_resources(path: Path) -> dict[int, dict[int | str, bytes]]:
    with path.open("rb") as stream:
        def read(offset: int, size: int) -> bytes:
            stream.seek(offset)
            data = stream.read(size)
            if len(data) != size:
                raise ValueError("Truncated executable resources")
            return data

        if read(0, 2) != b"MZ":
            raise ValueError("Not a Windows executable")
        pe = struct.unpack("<I", read(0x3C, 4))[0]
        header = read(pe, 24)
        if header[:4] != b"PE\0\0":
            raise ValueError("Invalid PE signature")
        section_count = struct.unpack_from("<H", header, 6)[0]
        optional_size = struct.unpack_from("<H", header, 20)[0]
        optional = read(pe + 24, optional_size)
        magic = struct.unpack_from("<H", optional)[0]
        directory_offset = {0x10B: 96, 0x20B: 112}.get(magic)
        if directory_offset is None:
            raise ValueError("Unsupported PE optional header")
        resource_rva, resource_size = struct.unpack_from("<II", optional, directory_offset + 16)
        if not resource_rva or not resource_size:
            raise ValueError("Executable has no resources")
        sections = []
        for index in range(section_count):
            section = read(pe + 24 + optional_size + index * 40, 40)
            virtual_size, address, raw_size, pointer = struct.unpack_from("<IIII", section, 8)
            sections.append((address, max(virtual_size, raw_size), pointer))

        def file_offset(rva: int) -> int:
            for address, size, pointer in sections:
                if address <= rva < address + size:
                    return pointer + rva - address
            raise ValueError("Resource RVA does not map to a PE section")

        base = file_offset(resource_rva)

        def entries(relative: int) -> list[tuple[int, int]]:
            header = read(base + relative, 16)
            count = sum(struct.unpack_from("<HH", header, 12))
            if count > 4096:
                raise ValueError("Invalid resource directory size")
            return [struct.unpack("<II", read(base + relative + 16 + index * 8, 8))
                    for index in range(count)]

        result = {}
        for kind, directory in entries(0):
            if kind not in (3, 14) or not directory & 0x80000000:
                continue
            result[kind] = {}
            for name, languages in entries(directory & 0x7FFFFFFF):
                if not languages & 0x80000000:
                    continue
                if name & 0x80000000:
                    relative = name & 0x7FFFFFFF
                    length = struct.unpack("<H", read(base + relative, 2))[0]
                    name = read(base + relative + 2, length * 2).decode("utf-16le")
                for _, leaf in entries(languages & 0x7FFFFFFF):
                    if leaf & 0x80000000:
                        continue
                    rva, size = struct.unpack_from("<II", read(base + leaf, 16))
                    result[kind][name] = read(file_offset(rva), size)
                    break
        return result


def verify(executable: Path, expected_icon: Path) -> dict:
    resources = executable_resources(executable)
    expected = Counter(hashlib.sha256(image).hexdigest() for image in icon_images(expected_icon))
    groups = []
    for group_id, data in resources.get(14, {}).items():
        _, kind, count = struct.unpack_from("<HHH", data)
        if kind != 1 or len(data) < 6 + count * 14:
            raise ValueError("Invalid executable icon group")
        hashes = []
        for index in range(count):
            resource_id = struct.unpack_from("<H", data, 6 + index * 14 + 12)[0]
            hashes.append(hashlib.sha256(resources[3][resource_id]).hexdigest())
        groups.append({"id": group_id, "images": count, "matches_ico": Counter(hashes) == expected})
    return {"executable": str(executable.resolve()), "icon": str(expected_icon.resolve()),
            "groups": groups, "passed": bool(groups) and any(group["matches_ico"] for group in groups)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("icon", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = verify(args.executable, args.icon)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["passed"] else 1)
