from __future__ import annotations

import asyncio
import json
import math
import os
import struct
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from threading import Lock
from typing import Any

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse

from asset_downloader import download_asset, log_missing_asset, strip_rbxh


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONVERTER_DIR = PROJECT_ROOT / "addons" / "rbxl_importer"
if str(CONVERTER_DIR) not in sys.path:
    sys.path.insert(0, str(CONVERTER_DIR))

import rbxl_converter  # noqa: E402


DEFAULT_MAX_FILE_SIZE = 500 * 1024 * 1024
MESH_PROPS = {"MeshId", "MeshID", "FileMesh", "CageMeshId"}
CSG_MESH_CLASSES = {"UnionOperation", "NegateOperation", "IntersectOperation"}
TEXTURE_HINT_PROPS = {
    "Texture",
    "TextureId",
    "TextureID",
    "TextureID",
    "Image",
    "ImageRectOffset",
    "LinkedSource",
    "ColorMap",
    "MetalnessMap",
    "NormalMap",
    "RoughnessMap",
    "SkyboxBk",
    "SkyboxDn",
    "SkyboxFt",
    "SkyboxLf",
    "SkyboxRt",
    "SkyboxUp",
}


app = FastAPI(title="Bobux RBXL Import Server", version="1.0.0")
jobs: dict[str, dict[str, Any]] = {}
jobs_lock = Lock()


def _cache_dir() -> Path:
    return Path(os.environ.get("CACHE_DIR", "./asset_cache")).resolve()


def _workers() -> int:
    try:
        return max(1, int(os.environ.get("WORKERS", "5")))
    except ValueError:
        return 5


def _max_file_size() -> int:
    try:
        return max(1, int(os.environ.get("MAX_FILE_SIZE", str(DEFAULT_MAX_FILE_SIZE))))
    except ValueError:
        return DEFAULT_MAX_FILE_SIZE


def _ensure_cache_dirs() -> None:
    root = _cache_dir()
    for name in ("meshes", "textures", "raw", "jobs"):
        (root / name).mkdir(parents=True, exist_ok=True)


def _job_dir(job_id: str) -> Path:
    path = _cache_dir() / "jobs" / job_id
    path.mkdir(parents=True, exist_ok=True)
    return path


def _update_status(job_id: str, **changes: Any) -> None:
    with jobs_lock:
        status = jobs.setdefault(
            job_id,
            {
                "status": "processing",
                "progress": 0.0,
                "stage": "queued",
                "parts_total": 0,
                "parts_done": 0,
                "missing_meshes": [],
                "error": "",
                "created_at": time.time(),
            },
        )
        status.update(changes)


@app.on_event("startup")
async def _startup() -> None:
    _ensure_cache_dirs()


@app.post("/import")
async def import_place(file: UploadFile = File(...)) -> JSONResponse:
    filename = file.filename or "place.rbxl"
    if not filename.lower().endswith((".rbxl", ".rbxlx")):
        raise HTTPException(status_code=400, detail="Only .rbxl and .rbxlx files are supported")
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Uploaded file is empty")
    if len(data) > _max_file_size():
        raise HTTPException(status_code=413, detail="Uploaded RBXL is larger than MAX_FILE_SIZE")

    _ensure_cache_dirs()
    job_id = str(uuid.uuid4())
    _update_status(job_id, status="processing", progress=0.0, stage="queued")
    asyncio.create_task(run_pipeline(job_id, filename, data))
    return JSONResponse({"job_id": job_id, "status": "processing"})


@app.get("/status/{job_id}")
async def import_status(job_id: str) -> JSONResponse:
    with jobs_lock:
        status = jobs.get(job_id)
        if not status:
            raise HTTPException(status_code=404, detail="Unknown import job")
        return JSONResponse(status)


@app.get("/result/{job_id}/scene.tscn")
async def import_scene(job_id: str) -> FileResponse:
    scene_path = _job_dir(job_id) / "scene.tscn"
    if not scene_path.exists():
        raise HTTPException(status_code=404, detail="Scene is not ready")
    return FileResponse(str(scene_path), media_type="text/plain", filename="scene.tscn")


@app.get("/result/{job_id}/assets")
async def import_assets(job_id: str) -> JSONResponse:
    manifest_path = _job_dir(job_id) / "assets.json"
    if not manifest_path.exists():
        raise HTTPException(status_code=404, detail="Asset manifest is not ready")
    return JSONResponse(json.loads(manifest_path.read_text(encoding="utf-8")))


@app.get("/result/{job_id}/assets/{asset_id}.glb")
async def import_asset_glb(job_id: str, asset_id: int) -> FileResponse:
    path = _cache_dir() / "meshes" / f"{asset_id}.glb"
    if not path.exists():
        raise HTTPException(status_code=404, detail="Converted mesh is not available")
    return FileResponse(str(path), media_type="model/gltf-binary", filename=f"{asset_id}.glb")


@app.get("/result/{job_id}/assets/{asset_id}.mesh.json")
async def import_asset_mesh_json(job_id: str, asset_id: int) -> FileResponse:
    path = _cache_dir() / "raw" / f"{asset_id}.mesh.json"
    if not path.exists():
        raise HTTPException(status_code=404, detail="Converted mesh JSON is not available")
    return FileResponse(str(path), media_type="application/json", filename=f"{asset_id}.mesh.json")


@app.get("/result/{job_id}/assets/{asset_id}.{extension}")
async def import_asset_file(job_id: str, asset_id: int, extension: str) -> FileResponse:
    if extension.lower() not in {"png", "jpg", "jpeg", "webp", "bin", "mesh"}:
        raise HTTPException(status_code=404, detail="Asset extension is not available")
    subdir = "textures" if extension.lower() in {"png", "jpg", "jpeg", "webp"} else "raw"
    path = _cache_dir() / subdir / f"{asset_id}.{extension.lower()}"
    if not path.exists():
        raise HTTPException(status_code=404, detail="Asset file is not available")
    media_type = {
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "webp": "image/webp",
        "mesh": "application/octet-stream",
        "bin": "application/octet-stream",
    }.get(extension.lower(), "application/octet-stream")
    return FileResponse(str(path), media_type=media_type, filename=path.name)


@app.get("/cache/stats")
async def cache_stats() -> JSONResponse:
    _ensure_cache_dirs()
    root = _cache_dir()
    counts: dict[str, int] = {}
    total_size = 0
    for subdir in ("meshes", "textures", "raw", "jobs"):
        files = [p for p in (root / subdir).rglob("*") if p.is_file()]
        counts[subdir] = len(files)
        total_size += sum(p.stat().st_size for p in files)
    return JSONResponse({"cache_dir": str(root), "counts": counts, "bytes": total_size})


async def run_pipeline(job_id: str, filename: str, rbxl_bytes: bytes) -> None:
    try:
        job_path = _job_dir(job_id)
        input_path = job_path / filename
        input_path.write_bytes(rbxl_bytes)

        _update_status(job_id, stage="parsing", progress=0.0)
        scene = await asyncio.to_thread(_parse_scene, input_path)
        (job_path / "intermediate.json").write_text(
            json.dumps(scene, ensure_ascii=False, separators=(",", ":"), allow_nan=False),
            encoding="utf-8",
        )
        _update_status(job_id, stage="parsing", progress=1.0)

        mesh_ids, texture_ids = extract_all_asset_ids(scene)
        all_asset_ids = sorted(mesh_ids | texture_ids)
        _update_status(
            job_id,
            stage="downloading",
            progress=0.0 if all_asset_ids else 1.0,
            parts_total=len(all_asset_ids),
            parts_done=0,
        )
        downloaded = await asyncio.to_thread(_download_assets_sync, job_id, all_asset_ids, mesh_ids, texture_ids)

        _update_status(job_id, stage="converting", progress=0.0)
        glb_ids = await asyncio.to_thread(_convert_meshes_sync, downloaded["mesh"])
        asset_manifest = {
            "meshes": glb_ids,
            "textures": _texture_records(downloaded["texture"]),
            "missing": downloaded["missing"],
        }
        (job_path / "assets.json").write_text(json.dumps(asset_manifest, separators=(",", ":")), encoding="utf-8")
        _update_status(job_id, stage="converting", progress=1.0)

        _update_status(job_id, stage="building", progress=0.0)
        await asyncio.to_thread(_build_tscn, job_id, scene, glb_ids, downloaded["missing"])
        _update_status(job_id, status="done", stage="done", progress=1.0)
    except Exception as exc:
        _update_status(job_id, status="error", stage="error", progress=1.0, error=str(exc))


def _parse_scene(input_path: Path) -> dict[str, Any]:
    result = rbxl_converter.parse_rbxl(str(input_path))
    warnings = result.setdefault("warnings", [])
    stats = {"non_finite": 0, "control_strings": 0, "compacted_strings": 0}
    return rbxl_converter.sanitize_for_strict_json(result, warnings, stats=stats)


def _extract_asset_id(value: Any) -> int:
    if value is None:
        return 0
    if isinstance(value, int):
        return value if value > 0 else 0
    if isinstance(value, float):
        return int(value) if math.isfinite(value) and value > 0 else 0
    if isinstance(value, dict):
        for key in ("asset_id", "id", "value", "url", "path"):
            candidate = _extract_asset_id(value.get(key))
            if candidate:
                return candidate
        return 0
    if isinstance(value, (list, tuple)):
        for child in value:
            candidate = _extract_asset_id(child)
            if candidate:
                return candidate
        return 0
    text = str(value)
    if not text:
        return 0
    import re

    patterns = (
        r"rbxassetid://(\d+)",
        r"assetdelivery\.roblox\.com/[^\s?]+[?&]id=(\d+)",
        r"roblox\.com/asset/[^\s?]+[?&]id=(\d+)",
        r"roblox\.com/library/(\d+)",
        r"[?&]id=(\d{3,})",
        r"^(\d{3,})$",
    )
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            try:
                return int(match.group(1))
            except ValueError:
                return 0
    return 0


def extract_all_asset_ids(scene: dict[str, Any]) -> tuple[set[int], set[int]]:
    mesh_ids: set[int] = set()
    texture_ids: set[int] = set()
    for inst in scene.get("instances", {}).values():
        if not isinstance(inst, dict):
            continue
        props = inst.get("properties", {})
        if not isinstance(props, dict):
            continue
        class_name = str(inst.get("class", ""))
        for prop_name, value in props.items():
            asset_id = _extract_asset_id(value)
            if not asset_id:
                continue
            lower = prop_name.lower()
            if prop_name in MESH_PROPS or lower.endswith("meshid") or lower == "mesh" or (class_name in CSG_MESH_CLASSES and lower in {"assetid", "sourceassetid"}):
                mesh_ids.add(asset_id)
            elif prop_name in TEXTURE_HINT_PROPS or "texture" in lower or "image" in lower or "skybox" in lower or lower.endswith("map"):
                texture_ids.add(asset_id)
    return mesh_ids, texture_ids


def _download_assets_sync(job_id: str, asset_ids: list[int], mesh_ids: set[int], texture_ids: set[int]) -> dict[str, Any]:
    results = {"mesh": [], "texture": [], "missing": []}
    if not asset_ids:
        return results
    with ThreadPoolExecutor(max_workers=_workers()) as pool:
        futures = {pool.submit(_download_and_cache, asset_id, asset_id in mesh_ids, asset_id in texture_ids): asset_id for asset_id in asset_ids}
        done = 0
        for future in as_completed(futures):
            asset_id = futures[future]
            done += 1
            try:
                kind = future.result()
            except Exception:
                kind = "missing"
            if kind == "mesh":
                results["mesh"].append(asset_id)
            elif kind == "texture":
                results["texture"].append(asset_id)
            else:
                results["missing"].append(asset_id)
                log_missing_asset(asset_id)
            _update_status(
                job_id,
                stage="downloading",
                progress=done / max(len(asset_ids), 1),
                parts_done=done,
                parts_total=len(asset_ids),
                missing_meshes=results["missing"],
            )
    return results


def _download_and_cache(asset_id: int, prefer_mesh: bool, prefer_texture: bool) -> str:
    cache = _cache_dir()
    mesh_path = cache / "raw" / f"{asset_id}.mesh"
    raw_path = cache / "raw" / f"{asset_id}.bin"
    if (cache / "meshes" / f"{asset_id}.glb").exists() or mesh_path.exists():
        return "mesh"
    texture_hit = _existing_texture_path(asset_id)
    if texture_hit:
        return "texture"
    if raw_path.exists():
        return "raw"

    if prefer_mesh:
        mesh_payload = rbxl_converter.resolve_roblox_asset_payload(asset_id, "mesh", timeout=10, use_storage=True)
        if mesh_payload and _is_mesh_payload(mesh_payload):
            mesh_path.write_bytes(mesh_payload)
            return "mesh"

    if prefer_texture:
        texture_payload = rbxl_converter.resolve_roblox_asset_payload(asset_id, "image", timeout=10, use_storage=True)
        ext = _image_extension(texture_payload) if texture_payload else ""
        if ext:
            (cache / "textures" / f"{asset_id}.{ext}").write_bytes(texture_payload)
            return "texture"

    payload = download_asset(asset_id)
    if not payload:
        return "missing"
    payload = strip_rbxh(payload)

    if _is_mesh_payload(payload) or prefer_mesh:
        if _is_mesh_payload(payload):
            mesh_path.write_bytes(payload)
            return "mesh"
        raw_path.write_bytes(payload)
        return "raw"

    ext = _image_extension(payload)
    if ext:
        (cache / "textures" / f"{asset_id}.{ext}").write_bytes(payload)
        return "texture"
    if prefer_texture:
        raw_path.write_bytes(payload)
        return "raw"
    raw_path.write_bytes(payload)
    return "raw"


def _existing_texture_path(asset_id: int) -> Path | None:
    for ext in ("png", "jpg", "jpeg", "webp"):
        path = _cache_dir() / "textures" / f"{asset_id}.{ext}"
        if path.exists():
            return path
    return None


def _texture_records(asset_ids: list[int]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for asset_id in sorted(set(asset_ids)):
        path = _existing_texture_path(asset_id)
        if path:
            records.append({"id": asset_id, "ext": path.suffix.lstrip(".").lower()})
    return records


def _is_mesh_payload(payload: bytes) -> bool:
    return any(
        marker in payload[:256]
        for marker in (
            b"version 1.00",
            b"version 1.01",
            b"version 2.00",
            b"version 3.00",
            b"version 3.01",
            b"version 4.00",
            b"version 4.01",
            b"version 5.00",
        )
    )


def _image_extension(payload: bytes) -> str:
    if payload.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if payload.startswith(b"\xff\xd8\xff"):
        return "jpg"
    if payload.startswith(b"RIFF") and payload[8:12] == b"WEBP":
        return "webp"
    return ""


def _convert_meshes_sync(asset_ids: list[int]) -> list[int]:
    converted: list[int] = []
    for asset_id in sorted(set(asset_ids)):
        source = _cache_dir() / "raw" / f"{asset_id}.mesh"
        target = _cache_dir() / "meshes" / f"{asset_id}.glb"
        if target.exists():
            converted.append(asset_id)
            continue
        if not source.exists():
            continue
        try:
            mesh_json = rbxl_converter._parse_roblox_mesh_payload(source.read_bytes())
            _write_mesh_json(asset_id, mesh_json)
            _write_glb_from_mesh_json(target, mesh_json)
            converted.append(asset_id)
        except Exception:
            log_missing_asset(asset_id)
    return converted


def _write_mesh_json(asset_id: int, mesh_json: dict[str, Any]) -> None:
    path = _cache_dir() / "raw" / f"{asset_id}.mesh.json"
    payload = dict(mesh_json)
    payload["asset_id"] = str(asset_id)
    path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":"), allow_nan=False), encoding="utf-8")


def _write_glb_from_mesh_json(path: Path, mesh_json: dict[str, Any]) -> None:
    positions = [float(v) for v in mesh_json.get("vertices", [])]
    normals = [float(v) for v in mesh_json.get("normals", [])]
    uvs = [float(v) for v in mesh_json.get("uvs", [])]
    indices = [int(v) for v in mesh_json.get("indices", [])]
    vertex_count = len(positions) // 3
    if vertex_count <= 0 or not indices:
        raise ValueError("mesh has no vertices or indices")
    if len(normals) != vertex_count * 3:
        normals = [0.0, 1.0, 0.0] * vertex_count
    if len(uvs) != vertex_count * 2:
        uvs = [0.0, 0.0] * vertex_count

    chunks: list[bytes] = []
    views: list[dict[str, Any]] = []
    accessors: list[dict[str, Any]] = []

    def add_blob(blob: bytes, target: int) -> int:
        offset = sum(len(chunk) for chunk in chunks)
        padding = (-offset) % 4
        if padding:
            chunks.append(b"\x00" * padding)
            offset += padding
        chunks.append(blob)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(blob), "target": target})
        return len(views) - 1

    pos_blob = struct.pack("<%df" % len(positions), *positions)
    norm_blob = struct.pack("<%df" % len(normals), *normals)
    uv_blob = struct.pack("<%df" % len(uvs), *uvs)
    idx_blob = struct.pack("<%dI" % len(indices), *indices)

    mins = [min(positions[i::3]) for i in range(3)]
    maxs = [max(positions[i::3]) for i in range(3)]
    pos_view = add_blob(pos_blob, 34962)
    norm_view = add_blob(norm_blob, 34962)
    uv_view = add_blob(uv_blob, 34962)
    idx_view = add_blob(idx_blob, 34963)

    accessors.extend(
        [
            {"bufferView": pos_view, "componentType": 5126, "count": vertex_count, "type": "VEC3", "min": mins, "max": maxs},
            {"bufferView": norm_view, "componentType": 5126, "count": vertex_count, "type": "VEC3"},
            {"bufferView": uv_view, "componentType": 5126, "count": vertex_count, "type": "VEC2"},
            {"bufferView": idx_view, "componentType": 5125, "count": len(indices), "type": "SCALAR"},
        ]
    )
    bin_chunk = b"".join(chunks)
    gltf = {
        "asset": {"version": "2.0", "generator": "Bobux RBXL Import Server"},
        "buffers": [{"byteLength": len(bin_chunk)}],
        "bufferViews": views,
        "accessors": accessors,
        "meshes": [
            {
                "primitives": [
                    {
                        "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                        "indices": 3,
                        "mode": 4,
                    }
                ]
            }
        ],
        "nodes": [{"mesh": 0, "name": "RobloxMesh"}],
        "scenes": [{"nodes": [0]}],
        "scene": 0,
    }
    json_chunk = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_chunk += b" " * ((-len(json_chunk)) % 4)
    bin_chunk += b"\x00" * ((-len(bin_chunk)) % 4)
    total_length = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    with path.open("wb") as handle:
        handle.write(struct.pack("<4sII", b"glTF", 2, total_length))
        handle.write(struct.pack("<I4s", len(json_chunk), b"JSON"))
        handle.write(json_chunk)
        handle.write(struct.pack("<I4s", len(bin_chunk), b"BIN\x00"))
        handle.write(bin_chunk)


def _build_tscn(job_id: str, scene: dict[str, Any], glb_ids: list[int], missing: list[int]) -> None:
    job_path = _job_dir(job_id)
    part_count = sum(1 for inst in scene.get("instances", {}).values() if isinstance(inst, dict) and inst.get("class") in {"Part", "MeshPart", "UnionOperation", "WedgePart", "CornerWedgePart"})
    lines = [
        "[gd_scene format=3]",
        "",
        "[node name=\"ImportedRobloxPlace\" type=\"Node3D\"]",
        f"metadata/roblox_import_job_id = \"{job_id}\"",
        f"metadata/roblox_part_count = {part_count}",
        f"metadata/roblox_mesh_count = {len(glb_ids)}",
        f"metadata/roblox_missing_asset_count = {len(missing)}",
        "",
    ]
    for index, asset_id in enumerate(glb_ids[:256]):
        lines.extend(
            [
                f"[node name=\"MeshAsset_{asset_id}\" type=\"Node3D\" parent=\".\"]",
                f"metadata/roblox_asset_id = {asset_id}",
                f"metadata/glb_path = \"res://server/asset_cache/meshes/{asset_id}.glb\"",
                f"position = Vector3({(index % 16) * 3}, 0, {(index // 16) * 3})",
                "",
            ]
        )
    (job_path / "scene.tscn").write_text("\n".join(lines), encoding="utf-8")
