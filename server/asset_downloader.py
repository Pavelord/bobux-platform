from __future__ import annotations

import gzip
import os
import platform
import sqlite3
import struct
from pathlib import Path
from typing import Optional

import requests


MISSING_LOG = Path(__file__).resolve().parent / "missing_assets.log"


def strip_rbxh(data: bytes) -> bytes:
    if not data:
        return b""
    if data[:2] == b"\x1f\x8b":
        try:
            data = gzip.decompress(data)
        except OSError:
            pass
    if data.startswith(b"RBXH"):
        payload = _decode_rbxh_payload(data)
        if payload:
            data = payload
    magic_candidates = (
        b"version 1.00",
        b"version 1.01",
        b"version 2.00",
        b"version 3.00",
        b"version 3.01",
        b"version 4.00",
        b"version 4.01",
        b"version 5.00",
        b"\x89PNG\r\n\x1a\n",
        b"\xff\xd8\xff",
        b"RIFF",
        b"<roblox",
        b"<?xml",
    )
    hits = [idx for marker in magic_candidates for idx in [data.find(marker)] if idx >= 0]
    if hits:
        return data[min(hits):]
    return data


def _decode_rbxh_payload(data: bytes) -> bytes:
    """Decode Roblox's local-cache wrapper without guessing at NUL bytes."""
    if len(data) < 36 or data[:4] != b"RBXH":
        return b""
    try:
        offset = 8
        link_length = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        if link_length > len(data) - offset:
            return b""
        offset += link_length
        # Rogue byte, HTTP status, serialized-header length, XXHash.
        if offset + 17 > len(data):
            return b""
        offset += 1
        _status = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        header_length = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        offset += 4
        content_length = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        offset += 8
        payload_offset = offset + header_length
        if payload_offset > len(data) or content_length > len(data) - payload_offset:
            return b""
        return data[payload_offset:payload_offset + content_length]
    except (OverflowError, struct.error):
        return b""


def _roblox_session() -> requests.Session:
    session = requests.Session()
    session.headers.update(
        {
            "User-Agent": "Roblox/WinInet",
            "Accept": "application/octet-stream,image/png,image/jpeg,image/webp,application/json,*/*",
        }
    )
    cookie = os.environ.get("ROBLOX_COOKIE", "").strip()
    if cookie:
        if cookie.startswith(".ROBLOSECURITY="):
            cookie = cookie.split("=", 1)[1]
        session.cookies.set(".ROBLOSECURITY", cookie, domain=".roblox.com")
    return session


def _download_with_cookie_auth(asset_id: int, request_timeout: float = 10, cdn_timeout: float = 30) -> Optional[bytes]:
    session = _roblox_session()
    try:
        r1 = session.get(
            f"https://assetdelivery.roblox.com/v1/asset/?id={asset_id}",
            allow_redirects=False,
            timeout=request_timeout,
        )
        if r1.status_code in (301, 302, 303, 307, 308):
            cdn_url = r1.headers.get("Location", "")
            if cdn_url:
                r2 = session.get(cdn_url, timeout=cdn_timeout)
                if r2.status_code == 200 and r2.content:
                    return strip_rbxh(r2.content)
        if r1.status_code == 200 and r1.content and not _looks_like_error_page(r1.content):
            return strip_rbxh(r1.content)
    except requests.RequestException:
        pass

    for url in (
        f"https://assetdelivery.roblox.com/v2/assetId/{asset_id}",
        f"https://assetdelivery.roblox.com/v2/asset/?id={asset_id}",
    ):
        try:
            r3 = session.get(url, timeout=request_timeout)
            if r3.status_code != 200:
                continue
            ctype = (r3.headers.get("Content-Type") or "").lower()
            if "application/json" not in ctype and r3.content and not _looks_like_error_page(r3.content):
                return strip_rbxh(r3.content)
            data = r3.json()
            locations = data.get("locations", [])
            if isinstance(data.get("data"), dict):
                locations = data["data"].get("locations", locations)
            for item in locations:
                if not isinstance(item, dict):
                    continue
                cdn = item.get("location", "")
                if not cdn:
                    continue
                r4 = session.get(cdn, timeout=cdn_timeout)
                if r4.status_code == 200 and r4.content:
                    return strip_rbxh(r4.content)
        except (ValueError, requests.RequestException):
            continue
    return None


def _looks_like_error_page(data: bytes) -> bool:
    stripped = data[:128].lstrip().lower()
    return stripped.startswith(b"<!doctype") or stripped.startswith(b"<html")


def _download_from_windows_storage(asset_id: int) -> Optional[bytes]:
    if platform.system() != "Windows":
        return None
    local_app_data = os.environ.get("LOCALAPPDATA", "")
    if not local_app_data:
        return None
    db_path = Path(local_app_data) / "Roblox" / "rbx-storage.db"
    if not db_path.exists():
        return None

    try:
        con = sqlite3.connect(str(db_path))
        try:
            columns = [row[1] for row in con.execute("PRAGMA table_info(files)").fetchall()]
            rows = []
            if "url" in columns:
                rows = con.execute(
                    "SELECT id, content FROM files WHERE url LIKE ?",
                    (f"%{asset_id}%",),
                ).fetchall()
            # Never fall back to scanning arbitrary cache rows. Roblox's local
            # cache stores opaque content blobs, and a broad scan can return an
            # unrelated mesh/texture for a completely different asset id.
            if not rows:
                return None
            for row_id, content in rows:
                candidate = _storage_payload_from_row(local_app_data, row_id, content)
                if not candidate:
                    continue
                return strip_rbxh(candidate)
        finally:
            con.close()
    except sqlite3.Error:
        return None
    return None


def _storage_payload_from_row(local_app_data: str, row_id, content) -> bytes:
    if content:
        return bytes(content)
    hex_id = row_id.hex() if isinstance(row_id, bytes) else str(row_id)
    candidates = [
        Path(local_app_data) / "Roblox" / "rbx-storage" / hex_id[:2] / hex_id,
        Path(local_app_data) / "Roblox" / hex_id[:2] / hex_id,
    ]
    for path in candidates:
        if path.exists():
            try:
                return path.read_bytes()
            except OSError:
                continue
    return b""


def _payload_has_asset_magic(data: bytes) -> bool:
    return any(
        marker in data
        for marker in (
            b"version 1.00",
            b"version 2.00",
            b"version 3.00",
            b"version 4.00",
            b"version 5.00",
            b"\x89PNG\r\n\x1a\n",
            b"\xff\xd8\xff",
            b"RIFF",
        )
    )


def log_missing_asset(asset_id: int) -> None:
    try:
        MISSING_LOG.parent.mkdir(parents=True, exist_ok=True)
        with MISSING_LOG.open("a", encoding="utf-8") as handle:
            handle.write(f"{asset_id}\n")
    except OSError:
        pass


def download_asset(
    asset_id: int,
    request_timeout: float = 10,
    cdn_timeout: float = 30,
    use_storage: bool = True,
) -> Optional[bytes]:
    payload = _download_with_cookie_auth(asset_id, request_timeout=request_timeout, cdn_timeout=cdn_timeout)
    if payload:
        return payload
    if use_storage:
        payload = _download_from_windows_storage(asset_id)
        if payload:
            return payload
    log_missing_asset(asset_id)
    return None
