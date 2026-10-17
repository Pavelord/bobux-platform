#!/usr/bin/env python3
"""Check a server release before upload without extracting or exposing secrets."""

from __future__ import annotations

import argparse
import tarfile
from pathlib import Path, PurePosixPath


REQUIRED_FILES = {
    "project.godot",
    "server/server_main.gd",
    "autoload/lua_script_engine.gd",
    "autoload/imported_place_network.gd",
    "addons/luaAPI/luaAPI.gdextension",
    "addons/luaAPI/bin/libbobuxluau.linux.template_debug.x86_64.so",
    "addons/luaAPI/bin/libbobuxluau.linux.template_release.x86_64.so",
    "services/bobux_api/server.js",
    "services/bobux_api/package.json",
    "services/bobux_api/package-lock.json",
    "services/bobux_api/map_list_query.mjs",
    "tools/server_release_transaction.py",
    "tools/validate_server_release_archive.py",
    "tools/validate_native_release_artifacts.py",
    "ops/vps/bobux_nginx.conf",
    "ops/vps/index.html",
}
FORBIDDEN_COMPONENTS = {
    ".git", ".godot", ".codex-tools", ".codex-tmp", ".dist", ".agents",
    ".venv", "__pycache__", ".pytest_cache", "node_modules", "dist",
    "game", "exiting_game", "launcher_export", "supabase",
    "export_templates", "practice_docx_work", "practice_render_ascii",
    "practice_report_exact_qa", "practice_report_qa", "stress_reports", "практика",
}
FORBIDDEN_SUFFIXES = {
    ".keystore", ".jks", ".p12", ".pfx", ".pem", ".key", ".sqlite",
    ".sqlite3", ".db", ".obj", ".o", ".os", ".a", ".lib", ".exp",
    ".pdb", ".map", ".pyc",
}


def validate_archive(path: Path) -> dict[str, int]:
    names: set[str] = set()
    unpacked_bytes = 0
    file_count = 0
    with tarfile.open(path, "r:gz") as archive:
        for member in archive:
            relative = PurePosixPath(member.name)
            normalized = relative.as_posix()
            if relative.is_absolute() or ".." in relative.parts or "\\" in member.name:
                raise ValueError("Server archive contains an unsafe extraction path.")
            if member.issym() or member.islnk():
                raise ValueError(f"Server archive contains a link at {normalized!r}; only regular resources are supported.")
            if any(part in FORBIDDEN_COMPONENTS for part in relative.parts):
                raise ValueError("Server archive contains excluded build/cache/repository files.")
            if normalized in {"autoload/supabase_client.gd", "autoload/supabase_client.gd.uid"}:
                raise ValueError("Server archive contains a retired legacy client.")
            if relative.parts[:2] == ("native", "luau_bridge") and any(
                part.startswith("build") for part in relative.parts[2:]
            ):
                raise ValueError("Server archive contains native build output.")
            if relative.parts[:4] == ("tools", "rbxl_compare", "rbxdom_oracle", "target"):
                raise ValueError("Server archive contains Rust diagnostic build output.")
            if relative.name == ".env" or (
                relative.name.startswith(".env.") and relative.name != ".env.example"
            ):
                raise ValueError("Server archive contains a protected environment file.")
            if relative.suffix.lower() in FORBIDDEN_SUFFIXES or ".sqlite" in relative.name.lower():
                raise ValueError("Server archive contains a credential, database, or intermediate file.")
            if relative.parts[:2] == ("services", "bobux_api") and any(
                part in {"data", "storage", "uploads"} for part in relative.parts[2:]
            ):
                raise ValueError("Server archive contains live API data.")
            if member.isfile():
                if normalized.startswith("addons/luaAPI/bin/libbobuxluau.") and member.size < 256 * 1024:
                    raise ValueError("Server archive contains an undersized native Luau library.")
                if normalized in names:
                    raise ValueError("Server archive contains a duplicate resource path.")
                names.add(normalized)
                file_count += 1
                unpacked_bytes += member.size
    missing = sorted(REQUIRED_FILES - names)
    if missing:
        raise ValueError("Server archive is missing required runtime resources: " + ", ".join(missing))
    return {"files": file_count, "unpacked_bytes": unpacked_bytes}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    summary = validate_archive(args.archive)
    print(
        f"Server archive validated: {summary['files']} files, "
        f"{summary['unpacked_bytes'] / 1048576:.1f} MiB unpacked; "
        "Linux Luau libraries and API are present, no caches or secrets."
    )


if __name__ == "__main__":
    main()
