#!/usr/bin/env python3
"""Snapshot and restore only release files, preserving live accounts and caches."""

from __future__ import annotations

import argparse
import json
import shutil
import tarfile
from pathlib import Path, PurePosixPath

NGINX_SITE = Path("/etc/nginx/sites-available/bobux")
RETIRED_LEGACY_PATHS = ("supabase", "autoload/supabase_client.gd", "autoload/supabase_client.gd.uid")

def protected_api_file(relative: Path) -> bool:
    return (
        any(part in {"data", "storage", "uploads"} for part in relative.parts)
        or relative.name == ".env" or relative.name.startswith(".env.") and relative.name != ".env.example"
        or ".sqlite" in relative.name.lower() or relative.suffix.lower() == ".db"
    )


def safe_target(root: Path, relative: str) -> Path:
    path = PurePosixPath(relative)
    if path.is_absolute() or ".." in path.parts or "\\" in relative:
        raise ValueError("Unsafe release path")
    target = root / path
    if not target.resolve().is_relative_to(root.resolve()) or target.is_symlink():
        raise ValueError("Release path resolves outside its root or is a link")
    return target


def copy_file(source: Path, destination: Path) -> None:
    if source.is_symlink() or not source.is_file():
        raise ValueError("Release snapshot expects regular files")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def api_files(root: Path) -> list[Path]:
    return sorted(path for path in root.rglob("*") if (path.is_file() or path.is_symlink()) and not protected_api_file(path.relative_to(root)))


def copy_api_entry(source: Path, destination: Path, source_root: Path) -> None:
    if source.is_symlink():
        if not source.resolve().is_relative_to(source_root.resolve()):
            raise ValueError("API dependency link resolves outside the API directory")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.symlink_to(source.readlink(), target_is_directory=source.is_dir())
    else:
        copy_file(source, destination)


def snapshot(args: argparse.Namespace) -> None:
    backup = args.backup.resolve()
    backup.mkdir(mode=0o700, parents=False, exist_ok=False)
    helper = Path(globals().get("__file__", ""))
    if helper.is_file():
        copy_file(helper, backup / "server_release_transaction.py")
    entries: list[str] = []
    with tarfile.open(args.archive, "r:gz") as archive:
        for member in archive:
            if member.isfile():
                entries.append(PurePosixPath(member.name).as_posix())
    server_files = []
    for relative in sorted(set(entries)):
        target = safe_target(args.server_root, relative)
        existed = target.is_file()
        server_files.append({"relative": relative, "existed": existed})
        if existed:
            copy_file(target, backup / "server" / relative)
    for source in api_files(args.api_root):
        copy_api_entry(source, backup / "api" / source.relative_to(args.api_root), args.api_root)
    web_files = [
        "downloads/Bobux-Windows.zip", "downloads/BobuxLauncher-Windows.zip",
        "downloads/BobuxSetup.exe", "downloads/Bobux-x86_64.AppImage",
        "downloads/desktop-latest.json", "downloads/latest.json",
        "launcher/latest.json", "mobile/latest.json", "mobile/Bobux-Android.apk",
        "index.html", "admin.html",
        "downloads/" + args.versioned_windows, "mobile/" + args.versioned_mobile,
    ]
    web_files += ["assets/" + relative.removeprefix("ops/vps/assets/") for relative in entries if relative.startswith("ops/vps/assets/")]
    web_entries = []
    for relative in web_files:
        target = safe_target(args.web_root, relative)
        existed = target.is_file()
        web_entries.append({"relative": relative, "existed": existed})
        if existed:
            copy_file(target, backup / "web" / relative)
    nginx = NGINX_SITE
    nginx_existed = nginx.is_file()
    if nginx_existed:
        copy_file(nginx, backup / "nginx.conf")
    manifest = {
        "server_root": str(args.server_root.resolve()), "api_root": str(args.api_root.resolve()),
        "web_root": str(args.web_root.resolve()), "server": server_files,
        "web": web_entries, "nginx_existed": nginx_existed,
        "retired_legacy": [relative for relative in RETIRED_LEGACY_PATHS if safe_target(args.server_root, relative).exists()],
    }
    (backup / "snapshot.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("Release rollback snapshot ready:", backup)


def retire_legacy(args: argparse.Namespace) -> None:
    backup = args.backup.resolve(strict=True)
    manifest = json.loads((backup / "snapshot.json").read_text(encoding="utf-8"))
    server_root = Path(manifest["server_root"])
    for relative in manifest.get("retired_legacy", []):
        source = safe_target(server_root, relative)
        destination = backup / "retired-supabase" / relative
        if source.exists():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(source), str(destination))
    print("Legacy Supabase files moved out of the active server into the private rollback snapshot.")


def restore_entries(root: Path, backup: Path, entries: list[dict]) -> None:
    for entry in entries:
        target = safe_target(root, entry["relative"])
        if entry["existed"]:
            copy_file(backup / entry["relative"], target)
        elif target.exists():
            if not target.is_file():
                raise ValueError("Refusing to remove a non-file during rollback")
            target.unlink()


def restore(args: argparse.Namespace) -> None:
    backup = args.backup.resolve(strict=True)
    manifest = json.loads((backup / "snapshot.json").read_text(encoding="utf-8"))
    server_root = Path(manifest["server_root"])
    api_root = Path(manifest["api_root"])
    web_root = Path(manifest["web_root"])
    restore_entries(server_root, backup / "server", manifest["server"])
    for relative in manifest.get("retired_legacy", []):
        source = backup / "retired-supabase" / relative
        destination = safe_target(server_root, relative)
        if source.exists():
            if destination.exists():
                raise ValueError("Refusing to overwrite a re-created legacy path during rollback")
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(source), str(destination))
    # Code and dependency files roll back together; account/storage/env files stay in place.
    for path in api_files(api_root):
        relative = path.relative_to(api_root)
        if path.is_symlink():
            if not path.resolve().is_relative_to(api_root.resolve()):
                raise ValueError("API dependency link resolves outside the API directory")
            path.unlink()
        else:
            safe_target(api_root, relative.as_posix()).unlink()
    for source in api_files(backup / "api"):
        copy_api_entry(source, safe_target(api_root, source.relative_to(backup / "api").as_posix()), backup / "api")
    restore_entries(web_root, backup / "web", manifest["web"])
    nginx = NGINX_SITE
    if manifest["nginx_existed"]:
        copy_file(backup / "nginx.conf", nginx)
    print("Release files restored from:", backup)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    save = subparsers.add_parser("snapshot")
    save.add_argument("--archive", type=Path, required=True)
    save.add_argument("--backup", type=Path, required=True)
    save.add_argument("--server-root", type=Path, required=True)
    save.add_argument("--api-root", type=Path, required=True)
    save.add_argument("--web-root", type=Path, required=True)
    save.add_argument("--versioned-windows", required=True)
    save.add_argument("--versioned-mobile", required=True)
    rollback = subparsers.add_parser("restore")
    rollback.add_argument("--backup", type=Path, required=True)
    retire = subparsers.add_parser("retire-legacy")
    retire.add_argument("--backup", type=Path, required=True)
    args = parser.parse_args()
    {"snapshot": snapshot, "restore": restore, "retire-legacy": retire_legacy}[args.action](args)


if __name__ == "__main__":
    main()
