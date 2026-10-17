#!/usr/bin/env python3
"""Verify every packaged Luau library against the frozen platform input."""

from __future__ import annotations

import argparse
import hashlib
import json
import tarfile
import zipfile
from pathlib import Path


MINIMUM_NATIVE_BYTES = 256 * 1024
BIN = "addons/luaAPI/bin/"
PLATFORMS = {
    "windows.template_debug.x86_64.dll": ("pe", 0x8664),
    "windows.template_release.x86_64.dll": ("pe", 0x8664),
    "windows.template_release.x86_32.dll": ("pe", 0x14C),
    "android.template_release.arm64.so": ("elf", 2, 183),
    "android.template_release.arm32.so": ("elf", 1, 40),
    "linux.template_debug.x86_64.so": ("elf", 2, 62),
    "linux.template_release.x86_64.so": ("elf", 2, 62),
}


def sha256_stream(stream) -> str:
    digest = hashlib.sha256()
    while data := stream.read(1024 * 1024):
        digest.update(data)
    return digest.hexdigest()


def source_identity(root: Path, suffix: str) -> dict:
    path = root / (BIN + "libbobuxluau." + suffix)
    if not path.is_file() or path.stat().st_size < MINIMUM_NATIVE_BYTES:
        raise ValueError("Native release input is missing or undersized: " + path.name)
    platform = PLATFORMS[suffix]
    with path.open("rb") as stream:
        header = stream.read(64)
        if platform[0] == "pe":
            if header[:2] != b"MZ":
                raise ValueError("Native DLL is not a PE library: " + path.name)
            stream.seek(int.from_bytes(header[60:64], "little"))
            pe = stream.read(6)
            if pe[:4] != b"PE\0\0" or int.from_bytes(pe[4:6], "little") != platform[1]:
                raise ValueError("Native DLL architecture mismatch: " + path.name)
        elif header[:4] != b"\x7fELF" or header[4] != platform[1] or int.from_bytes(header[18:20], "little") != platform[2]:
            raise ValueError("Native ELF architecture mismatch: " + path.name)
        stream.seek(0)
        digest = sha256_stream(stream)
    return {"size": path.stat().st_size, "sha256": digest}


def packaged_libraries(kind: str, architecture: str = "x86_32") -> dict[str, str]:
    if kind == "apk":
        return {
            "lib/arm64-v8a/libbobuxluau.android.template_release.arm64.so": "android.template_release.arm64.so",
            "lib/armeabi-v7a/libbobuxluau.android.template_release.arm32.so": "android.template_release.arm32.so",
        }
    if kind == "windows":
        suffix = "windows.template_release." + architecture + ".dll"
        return {BIN + "libbobuxluau." + suffix: suffix}
    if kind == "linux":
        # Godot places exported Linux GDExtensions beside the executable.
        return {"Bobux/libbobuxluau.linux.template_release.x86_64.so": "linux.template_release.x86_64.so"}
    if kind == "server":
        return {BIN + "libbobuxluau.linux." + target + ".x86_64.so": "linux." + target + ".x86_64.so"
                for target in ("template_debug", "template_release")}
    raise ValueError("Unknown native package kind")


def validate_native_archive(kind: str, archive: Path, root: Path, architecture: str = "x86_32") -> list[dict]:
    required = packaged_libraries(kind, architecture)
    identities = {name: source_identity(root, suffix) for name, suffix in required.items()}
    results = []
    if kind in {"apk", "windows"}:
        with zipfile.ZipFile(archive) as package:
            for name, expected in identities.items():
                entries = [entry for entry in package.infolist() if entry.filename.replace("\\", "/") == name]
                if not entries:
                    raise ValueError("Packaged native library is missing required entry: " + name)
                if len(entries) != 1:
                    raise ValueError("Packaged native library is duplicate: " + name)
                if entries[0].file_size != expected["size"]:
                    raise ValueError(f"Packaged native library size differs from source: {name} ({entries[0].file_size} bytes, expected {expected['size']})")
                with package.open(entries[0]) as stream:
                    digest = sha256_stream(stream)
                if digest != expected["sha256"]:
                    raise ValueError("Packaged native library SHA-256 differs from source: " + name)
                results.append({"path": name, **expected})
    else:
        with tarfile.open(archive, "r:gz") as package:
            entries = {}
            for member in package:
                name = member.name.removeprefix("./")
                if name in required:
                    if name in entries or not member.isfile():
                        raise ValueError("Packaged native library is duplicate or a link: " + name)
                    stream = package.extractfile(member)
                    if stream is None:
                        raise ValueError("Could not read packaged native library: " + name)
                    with stream:
                        entries[name] = {"size": member.size, "sha256": sha256_stream(stream)}
            for name, expected in identities.items():
                if name not in entries:
                    raise ValueError("Packaged native library is missing required entry: " + name)
                if entries[name]["size"] != expected["size"]:
                    raise ValueError(f"Packaged native library size differs from source: {name} ({entries[name]['size']} bytes, expected {expected['size']})")
                if entries[name]["sha256"] != expected["sha256"]:
                    raise ValueError("Packaged native library SHA-256 differs from source: " + name)
                results.append({"path": name, **expected})
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("snapshot", "unchanged", "apk", "windows", "linux", "server"))
    parser.add_argument("path", type=Path)
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--windows-architecture", choices=("x86_32", "x86_64"), default="x86_32")
    args = parser.parse_args()
    if args.kind in {"snapshot", "unchanged"}:
        identities = {suffix: source_identity(args.source_root, suffix) for suffix in PLATFORMS}
        if args.kind == "snapshot":
            args.path.write_text(json.dumps(identities, indent=2) + "\n", encoding="utf-8")
        elif json.loads(args.path.read_text(encoding="utf-8")) != identities:
            raise ValueError("Native inputs changed while exporting; rebuild the release after native compilation stops.")
        print("Native inputs:", args.kind, "PASS, 7 platform libraries checked")
    else:
        results = validate_native_archive(args.kind, args.path, args.source_root, args.windows_architecture)
        print("Packaged Luau integrity PASS:", args.kind, len(results), "libraries, exact architecture/size/SHA-256")


if __name__ == "__main__":
    main()
