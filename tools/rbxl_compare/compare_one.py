#!/usr/bin/env python3
"""Compare Bobux's parsed place tree with a rbx-dom JSONL oracle dump."""

from __future__ import annotations

import argparse
import base64
import collections
import gzip
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]
CONVERTER_PATH = ROOT / "addons" / "rbxl_importer_v2" / "rbxl_converter_v2.py"
REF_PROPERTY_NAMES = {
    "adornee", "attachment0", "attachment1", "camerasubject", "character",
    "currentcamera", "object", "part0", "part1", "player", "primarypart",
    "target", "targettextchannel", "terrain", "linkedsource", "soundgroup",
    "rootlocalizationtable", "hoverhapticeffect", "presshapticeffect",
    "part0internal", "part1internal", "hole", "sidechain", "listenerobject",
    "studiodefaultstylesheet", "studioinsertwidgetlayercollectorautolinkstylesheet",
    "nextselectiondown", "nextselectionleft", "nextselectionright", "nextselectionup",
    "selectionimageobject", "playertohidefrom", "instance",
}
BINARY_STRING_PROPERTIES = {
    "aeromeshdata", "childdata", "childdata2", "meshdata", "meshdata2",
    "loddata", "materials", "modelmeshdata", "physicsdata", "physicalconfigdata", "serializeddefaultattributes", "smoothgrid",
    "serializedemulatedpolicyinfo", "studiodefaultstylesheet", "commitinflightguid",
    "studioinsertwidgetlayercollectorautolinkstylesheet", "accessoryrigidandlayeredblob", "slimhash",
    "originalscriptguid",
}
BASE_PART_CLASSES = {
    "part", "wedgepart", "cornerwedgepart", "trusspart", "meshpart", "unionoperation",
    "seat", "vehicleseat", "spawnlocation", "terrain",
}
BRICK_COLOR_RGB = {}
try:
    palette_path = ROOT / "addons" / "roblox_runtime" / "brick_color_palette.gd"
    for line in palette_path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"\s*(\d+)\s*:\s*Color8\((\d+),\s*(\d+),\s*(\d+)\)", line)
        if match:
            brick_id, red, green, blue = map(int, match.groups())
            BRICK_COLOR_RGB[brick_id] = [red / 255.0, green / 255.0, blue / 255.0]
except OSError:
    pass
VARIANT_TAGS = {
    "Attributes", "Axes", "BinaryString", "Bool", "BrickColor", "CFrame", "Color3",
    "Color3uint8", "ColorSequence", "Content", "ContentId", "Enum", "EnumItem",
    "Faces", "Float32", "Float64", "Font", "Int32", "Int64", "MaterialColors",
    "NetAssetRef", "NumberRange", "NumberSequence", "OptionalCFrame",
    "PhysicalProperties", "Ray", "Rect", "Region3", "Region3int16", "Ref",
    "SecurityCapabilities", "SharedString", "String", "Tags", "UDim", "UDim2",
    "UniqueId", "Vector2", "Vector2int16", "Vector3", "Vector3int16",
}


def load_converter():
    spec = importlib.util.spec_from_file_location("rbxl_converter_v2", CONVERTER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load Bobux converter at {CONVERTER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _short(value, limit=240):
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    if len(text) <= limit:
        return value
    return text[:limit] + "…"


def _path_text(identity):
    if not identity:
        return "<root>"
    return "/".join(f"{segment[0]}:{segment[1]}[{segment[2]}]" for segment in identity)


def _identity_key(identity):
    return tuple((str(part[0]), str(part[1]), int(part[2])) for part in identity)


def _hash_bytes(data: bytes):
    return {"__bytes_sha256": hashlib.sha256(data).hexdigest(), "byte_length": len(data)}


def _decode_base64(value):
    try:
        return base64.b64decode(value, validate=True)
    except Exception:
        return None


def _canon_number(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, (float, int)):
        if isinstance(value, float) and not math.isfinite(value):
            return {"__non_finite": "NaN" if math.isnan(value) else ("+Inf" if value > 0 else "-Inf")}
    return value


def _canon_unique_id(value):
    """Normalize rbx-dom's 32-hex UniqueId into Bobux's decoded components."""
    if not isinstance(value, str) or len(value) != 32:
        return value
    try:
        int(value, 16)
    except ValueError:
        return value
    random_bits = int(value[:16], 16)
    random_signed = random_bits if random_bits < (1 << 63) else random_bits - (1 << 64)
    return {
        "epoch": int(value[16:24], 16),
        "index": int(value[24:32], 16),
        "random": random_signed,
    }


def _canon_shape(value):
    if isinstance(value, float):
        return _canon_number(value)
    if isinstance(value, list):
        return [_canon_shape(item) for item in value]
    if isinstance(value, dict):
        result = {}
        for key, child in value.items():
            # rbx-dom exposes the CFrame matrix as "orientation"; Bobux calls it
            # "rotation". Both are the same row-major basis matrix.
            canonical_key = "rotation" if key == "orientation" else key.casefold()
            result[canonical_key] = _canon_shape(child)
        return result
    return value


def _canon_dom(value, id_to_identity):
    if isinstance(value, dict):
        if "__rbxdom_ref_target_id" in value:
            target_id = value["__rbxdom_ref_target_id"]
            target = id_to_identity.get(target_id) if target_id is not None else None
            return {"__ref_target": target}
        if "__roblox_non_finite_number" in value:
            return {"__non_finite": value["__roblox_non_finite_number"]}
        if "__rbxdom_digest" in value:
            return {"__digest": value["__rbxdom_digest"], "bytes": value.get("__rbxdom_serialized_bytes")}
        if "__rbxdom_binary_sha256" in value:
            return {"__bytes_sha256": value["__rbxdom_binary_sha256"], "byte_length": value.get("byte_length")}
        if "__rbxdom_serde_error" in value:
            return {"__serde_error": value["__rbxdom_serde_error"]}
        if len(value) == 1:
            tag, inner = next(iter(value.items()))
            if tag in VARIANT_TAGS:
                if tag == "UniqueId":
                    return _canon_unique_id(inner)
                if tag == "Attributes" and isinstance(inner, dict):
                    return {key.casefold(): _canon_dom_attribute(item, id_to_identity) for key, item in inner.items()}
                if tag in {"BinaryString", "SharedString"} and isinstance(inner, str):
                    decoded = _decode_base64(inner)
                    if decoded is not None:
                        return _hash_bytes(decoded)
                if tag == "Color3uint8":
                    if isinstance(inner, dict):
                        channels = [inner.get("r", inner.get("R")), inner.get("g", inner.get("G")), inner.get("b", inner.get("B"))]
                    else:
                        channels = inner
                    if isinstance(channels, list) and len(channels) == 3:
                        return [float(channel) / 255.0 for channel in channels]
                if tag == "PhysicalProperties":
                    if inner == "Default":
                        return {"custom": False}
                    if isinstance(inner, dict):
                        inner = {**inner, "custom": True}
                if tag == "CFrame" and isinstance(inner, dict):
                    inner = {"position": inner.get("position"), "rotation": inner.get("orientation")}
                elif tag == "OptionalCFrame" and isinstance(inner, dict):
                    inner = {"present": True, "cframe": {
                        "position": inner.get("position"),
                        "rotation": inner.get("orientation"),
                    }}
                elif tag == "UDim" and isinstance(inner, list) and len(inner) == 2:
                    inner = {"scale": inner[0], "offset": inner[1]}
                elif tag == "Rect" and isinstance(inner, list) and len(inner) == 2:
                    inner = {"min": inner[0], "max": inner[1]}
                elif tag == "UDim2" and isinstance(inner, list) and len(inner) == 2:
                    inner = {"x": {"scale": inner[0][0], "offset": inner[0][1]},
                             "y": {"scale": inner[1][0], "offset": inner[1][1]}}
                elif tag == "NumberSequence" and isinstance(inner, dict):
                    inner = inner.get("keypoints", inner)
                elif tag == "ColorSequence" and isinstance(inner, dict):
                    inner = inner.get("keypoints", inner)
                    if isinstance(inner, list):
                        inner = [{key: item for key, item in point.items() if key != "envelope"}
                                 if isinstance(point, dict) else point for point in inner]
                elif tag == "Font" and isinstance(inner, dict):
                    weight_names = {
                        "Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400,
                        "Medium": 500, "SemiBold": 600, "Bold": 700, "ExtraBold": 800,
                        "Heavy": 900,
                    }
                    style_names = {"Normal": 0, "Italic": 1}
                    weight = inner.get("weight")
                    style = inner.get("style")
                    inner = {
                        "family": inner.get("family"),
                        "weight": weight_names.get(weight, weight),
                        "style": style_names.get(style, style),
                        "cachedFaceId": inner.get("cachedFaceId") or "",
                    }
                elif tag in {"Content", "ContentId"} and isinstance(inner, dict):
                    if "Uri" in inner:
                        inner = inner.get("Uri")
                    elif "None" in inner:
                        inner = ""
                elif tag in {"Content", "ContentId"} and isinstance(inner, str) and inner.casefold() == "none":
                    inner = ""
                elif tag == "Ref":
                    # Ref is intercepted by the oracle before serialization.
                    return {"__ref_target": None}
                return _canon_dom(inner, id_to_identity)
        if "__roblox_non_finite_number" in value:
            return {"__non_finite": value["__roblox_non_finite_number"]}
        return _canon_shape(value)
    if isinstance(value, list):
        return [_canon_dom(item, id_to_identity) for item in value]
    return _canon_number(value)


def _canon_dom_attribute(value, id_to_identity):
    if isinstance(value, dict) and len(value) == 1:
        tag, inner = next(iter(value.items()))
        if tag == "BinaryString" and isinstance(inner, str):
            decoded = _decode_base64(inner)
            if decoded is not None:
                try:
                    return decoded.decode("utf-8")
                except UnicodeDecodeError:
                    return _hash_bytes(decoded)
        if tag == "Color3uint8":
            return _canon_dom(value, id_to_identity)
        if tag == "BrickColor":
            return _canon_dom(inner, id_to_identity)
        return _canon_dom(value, id_to_identity)
    return _canon_dom(value, id_to_identity)


def _canon_dom_property(value, property_name, id_to_identity):
    if property_name.casefold() == "originalscriptguid" and isinstance(value, dict) and set(value) == {"BinaryString"}:
        raw = _decode_base64(value["BinaryString"])
        if raw is not None:
            return raw.decode("utf-8", errors="replace")
    return _canon_dom(value, id_to_identity)


def _canon_bobux(value, property_name, id_to_identity, bobux_ref_to_identity, owner_class=""):
    if owner_class.casefold() == "screengui" and property_name.casefold() == "ignoreguiinset" and isinstance(value, bool):
        # Current Roblox reflection migration maps the legacy boolean to the
        # corresponding safe-area enum when ScreenInsets was not serialized.
        return 1 if value else 2
    if property_name.casefold() == "brickcolor" and isinstance(value, int) and not isinstance(value, bool):
        return BRICK_COLOR_RGB.get(value, {"__brickcolor_id": value})
    if owner_class.casefold() == "bodycolors" and property_name.casefold().endswith("color") and isinstance(value, int):
        return BRICK_COLOR_RGB.get(value, {"__brickcolor_id": value})
    property_key = property_name.casefold()
    owner_key = owner_class.casefold()
    numeric_asset_properties = {
        "charactermesh": {"meshid", "basetextureid", "overlaytextureid"},
        "hopperbin": {"textureid"},
        "imagehandleadornment": {"image"},
    }
    if owner_key in numeric_asset_properties and property_key in numeric_asset_properties[owner_key] and isinstance(value, int) and not isinstance(value, bool):
        return "" if value == 0 else f"rbxassetid://{value}"
    is_reference = property_key in REF_PROPERTY_NAMES or (
        property_key == "value" and owner_class.casefold() == "objectvalue"
    ) or (property_key == "instance" and owner_class.casefold() == "bodypartdescription")
    if isinstance(value, str) and property_key in BINARY_STRING_PROPERTIES:
        return _hash_bytes(value.encode("utf-8"))
    if property_name.casefold() in {"uniqueid", "historyid", "originalscriptguid"} and isinstance(value, dict) and set(value) == {"epoch", "index", "random"}:
        try:
            bits = int(value["random"]) & 0xFFFFFFFFFFFFFFFF
            return {
                "epoch": int(value["epoch"]) & 0xFFFFFFFF,
                "index": int(value["index"]) & 0xFFFFFFFF,
                "random": bits if bits < (1 << 63) else bits - (1 << 64),
            }
        except (TypeError, ValueError):
            pass
    if is_reference and isinstance(value, int) and not isinstance(value, bool):
        target = None if value < 0 else bobux_ref_to_identity.get(str(value))
        return {"__ref_target": target}
    if isinstance(value, dict):
        if set(value) == {"present", "cframe"} and not value.get("present"):
            return None
        if "__bobux_binary_base64" in value:
            decoded = _decode_base64(value.get("__bobux_binary_base64", ""))
            if decoded is not None:
                return _hash_bytes(decoded)
        if "__roblox_non_finite_number" in value:
            return {"__non_finite": value["__roblox_non_finite_number"]}
        if is_reference and set(value) == {"ref"}:
            ref_value = str(value["ref"])
            return {"__ref_target": bobux_ref_to_identity.get(ref_value)}
        if is_reference and set(value) == {"source", "ref"}:
            ref_value = str(value["ref"])
            return {"__ref_target": bobux_ref_to_identity.get(ref_value)}
        if set(value) == {"min", "max"}:
            points = []
            for key in ("min", "max"):
                point = value[key]
                if isinstance(point, dict) and "x" in point and "y" in point:
                    points.append([_canon_bobux(point["x"], key, id_to_identity, bobux_ref_to_identity, owner_class),
                                   _canon_bobux(point["y"], key, id_to_identity, bobux_ref_to_identity, owner_class)])
                elif isinstance(point, list) and len(point) == 2:
                    points.append([_canon_bobux(point[0], key, id_to_identity, bobux_ref_to_identity, owner_class),
                                   _canon_bobux(point[1], key, id_to_identity, bobux_ref_to_identity, owner_class)])
                else:
                    points = []
                    break
            if points:
                return {"min": points[0], "max": points[1]}
        return {key.casefold(): _canon_bobux(child, key, id_to_identity, bobux_ref_to_identity, owner_class)
                for key, child in value.items()}
    if isinstance(value, list):
        if property_name.casefold() == "color" and value and all(isinstance(item, dict) and "time" in item and "color" in item for item in value):
            value = [{key: child for key, child in item.items() if key != "envelope"} for item in value]
        return [_canon_bobux(item, property_name, id_to_identity, bobux_ref_to_identity, owner_class) for item in value]
    if isinstance(value, str) and len(value.encode("utf-8")) > 64 * 1024:
        return {"__digest": hashlib.sha256(value.encode("utf-8")).hexdigest(), "bytes": len(value.encode("utf-8"))}
    if isinstance(value, str) and value.casefold() == "none" and property_name.casefold().endswith(("id", "content", "texture", "image", "mesh")):
        return ""
    return _canon_number(value)


def _equal(left, right, tolerance=1e-6):
    if isinstance(left, dict) and set(left) == {"__non_finite"} and right is None:
        return True
    if isinstance(right, dict) and set(right) == {"__non_finite"} and left is None:
        return True
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        if isinstance(left, float) and not math.isfinite(left):
            return left == right or (math.isnan(left) and isinstance(right, float) and math.isnan(right))
        if isinstance(right, float) and not math.isfinite(right):
            return False
        return math.isclose(float(left), float(right), rel_tol=tolerance, abs_tol=tolerance)
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(_equal(left[key], right[key], tolerance) for key in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(_equal(a, b, tolerance) for a, b in zip(left, right))
    return left == right


def _read_dom_oracle(path):
    header = None
    footer = None
    instances = []
    with gzip.open(path, "rt", encoding="utf-8") as source:
        for line in source:
            row = json.loads(line)
            kind = row.get("record")
            if kind == "header":
                header = row
            elif kind == "footer":
                footer = row
            elif kind == "instance":
                row["identity"] = _identity_key(row.get("identity", []))
                instances.append(row)
    if header is None or footer is None:
        raise ValueError("rbx-dom dump lacks its header or footer")
    return header, footer, instances


def _build_bobux_identity(result):
    instances = result.get("instances", {})
    parents = {}
    children = collections.defaultdict(list)
    for edge in result.get("hierarchy", []):
        child = str(edge.get("child"))
        parent = str(edge.get("parent"))
        parents[child] = parent
        children[parent].append(child)
    for key in instances:
        if str(key) not in parents:
            parents[str(key)] = "-1"
            children["-1"].append(str(key))

    identity_by_ref = {}
    visiting = set()

    def resolve(ref):
        ref = str(ref)
        if ref in identity_by_ref:
            return identity_by_ref[ref]
        if ref in visiting:
            raise ValueError(f"cycle in Bobux hierarchy at referent {ref}")
        visiting.add(ref)
        node = instances[ref]
        class_name = str(node.get("class", ""))
        props = node.get("properties", {})
        name = props.get("Name", class_name) if isinstance(props, dict) else class_name
        parent = parents.get(ref, "-1")
        if parent in instances:
            parent_identity = resolve(parent)
        else:
            parent_identity = ()
        siblings = children.get(parent, [])
        ordinal = 0
        for sibling in siblings:
            sibling_node = instances.get(sibling, {})
            sibling_props = sibling_node.get("properties", {})
            sibling_name = sibling_props.get("Name", sibling_node.get("class", "")) if isinstance(sibling_props, dict) else sibling_node.get("class", "")
            if sibling_node.get("class") == class_name and sibling_name == name:
                if sibling == ref:
                    break
                ordinal += 1
        identity = parent_identity + ((class_name, str(name), ordinal),)
        visiting.remove(ref)
        identity_by_ref[ref] = identity
        return identity

    records = []
    by_identity = {}
    for ref, node in instances.items():
        ref = str(ref)
        identity = resolve(ref)
        record = {
            "id": ref,
            "class": str(node.get("class", "")),
            "name": str(node.get("properties", {}).get("Name", node.get("class", ""))),
            "identity": identity,
            "properties": node.get("properties", {}) if isinstance(node.get("properties", {}), dict) else {},
        }
        records.append(record)
        if identity in by_identity:
            by_identity[identity].append(record)
        else:
            by_identity[identity] = [record]
    return records, by_identity, identity_by_ref


def _unique_id_key(properties, side):
    value = next((item for key, item in properties.items() if str(key).casefold() == "uniqueid"), None)
    if side == "rbx_dom" and isinstance(value, dict) and len(value) == 1 and "UniqueId" in value:
        value = value["UniqueId"]
    if side == "bobux" and isinstance(value, dict) and set(value) == {"epoch", "index", "random"}:
        try:
            key = (int(value["epoch"]) & 0xFFFFFFFF, int(value["index"]) & 0xFFFFFFFF,
                   ((int(value["random"]) + (1 << 64)) if int(value["random"]) < 0 else int(value["random"])) & 0xFFFFFFFFFFFFFFFF)
            return key if any(key) else None
        except (TypeError, ValueError):
            return None
    if isinstance(value, str) and len(value) == 32:
        try:
            int(value, 16)
            key = (int(value[16:24], 16), int(value[24:32], 16), int(value[:16], 16))
            return key if any(key) else None
        except ValueError:
            return None
    return None


def _canonical_property_name(class_name, property_name):
    key = property_name.casefold()
    class_key = class_name.casefold()
    if key in {"formfactorraw", "formfactor"}:
        return "formfactor"
    if key == "brickcolor" and class_key in BASE_PART_CLASSES:
        return "color"
    if key == "originalscriptguid":
        return "originalscriptguid"
    if key in {"materialvariantserialized", "materialvariant"}:
        return "materialvariant"
    if key == "scalefactor":
        return "scale"
    if key in {"definescapabilities", "sandboxed"}:
        return "sandboxed"
    if key == "attributesserialize":
        return "attributes"
    if class_name.casefold() == "sound" and key in {"soundid", "audiocontent"}:
        return "audiocontent"
    if class_name.casefold() == "meshpart" and key in {"meshid", "meshcontent"}:
        return "meshcontent"
    if class_key == "unionoperation" and key in {"assetid", "content"}:
        return "content"
    if class_key == "animation" and key in {"animationid", "animationcontent"}:
        return "animationcontent"
    if class_key in {"imagelabel", "imagebutton"} and key in {"image", "imagecontent"}:
        return "imagecontent"
    if class_key == "imagebutton" and key in {"hoverimage", "hoverimagecontent"}:
        return "hoverimagecontent"
    if class_key == "imagebutton" and key in {"pressedimage", "pressedimagecontent"}:
        return "pressedimagecontent"
    if class_key == "scrollingframe" and key in {"topimage", "topimagecontent", "midimage", "midimagecontent", "bottomimage", "bottomimagecontent"}:
        return key if key.endswith("content") else key + "content"
    if class_key == "weldconstraint" and key in {"part0internal", "part0"}:
        return "part0"
    if class_key == "weldconstraint" and key in {"part1internal", "part1"}:
        return "part1"
    if class_key == "screengui" and key in {"ignoreguiinset", "screeninsets"}:
        return "screeninsets"
    if class_key == "sound":
        sound_aliases = {
            "emittersize": "rolloffmindistance", "rolloffmindistance": "rolloffmindistance",
            "xmlread_maxdistance_3": "rolloffmaxdistance", "maxdistance": "rolloffmaxdistance",
            "rolloffmaxdistance": "rolloffmaxdistance", "pitch": "playbackspeed",
            "playbackspeed": "playbackspeed", "soundid": "audiocontent",
            "audiocontent": "audiocontent",
        }
        if key in sound_aliases:
            return sound_aliases[key]
    if class_key == "camera" and key in {"coordinateframe", "cframe"}:
        return "cframe"
    if class_key == "bodycolors" and key in {
        "headcolor", "headcolor3", "leftarmcolor", "leftarmcolor3", "rightarmcolor", "rightarmcolor3",
        "leftlegcolor", "leftlegcolor3", "rightlegcolor", "rightlegcolor3", "torsocolor", "torsocolor3",
    }:
        return key if key.endswith("3") else key + "3"
    if class_key == "fire" and key in {"heat_xml", "heat", "size_xml", "size"}:
        return "heat" if key.startswith("heat") else "size"
    if class_key == "smoke" and key in {"opacity_xml", "opacity", "risevelocity_xml", "risevelocity", "size_xml", "size"}:
        return "opacity" if key.startswith("opacity") else ("risevelocity" if key.startswith("risevelocity") else "size")
    content_property_aliases = {
        "clickdetector": {"cursoricon": "cursoriconcontent", "cursoriconcontent": "cursoriconcontent"},
        "tool": {"textureid": "texturecontent", "texturecontent": "texturecontent"},
        "specialmesh": {"textureid": "texturecontent", "texturecontent": "texturecontent"},
        "decal": {
            "texture": "texturecontent", "textureid": "texturecontent", "texturecontent": "texturecontent",
            "metalnessmap": "metalnessmapcontent", "metalnessmapcontent": "metalnessmapcontent",
            "normalmap": "normalmapcontent", "normalmapcontent": "normalmapcontent",
            "roughnessmap": "roughnessmapcontent", "roughnessmapcontent": "roughnessmapcontent",
        },
        "texture": {
            "texture": "texturecontent", "textureid": "texturecontent", "texturecontent": "texturecontent",
            "metalnessmap": "metalnessmapcontent", "metalnessmapcontent": "metalnessmapcontent",
            "normalmap": "normalmapcontent", "normalmapcontent": "normalmapcontent",
            "roughnessmap": "roughnessmapcontent", "roughnessmapcontent": "roughnessmapcontent",
        },
        "shirtgraphic": {"graphic": "texturecontent", "graphiccontent": "texturecontent", "texturecontent": "texturecontent"},
        "surfaceappearance": {
            "colormap": "colormapcontent", "colormapcontent": "colormapcontent",
            "metalnessmap": "metalnessmapcontent", "metalnessmapcontent": "metalnessmapcontent",
            "normalmap": "normalmapcontent", "normalmapcontent": "normalmapcontent",
            "roughnessmap": "roughnessmapcontent", "roughnessmapcontent": "roughnessmapcontent",
            "texturepack": "texturepackcontent", "texturepackcontent": "texturepackcontent",
        },
        "materialvariant": {
            "colormap": "colormapcontent", "colormapcontent": "colormapcontent",
            "metalnessmap": "metalnessmapcontent", "metalnessmapcontent": "metalnessmapcontent",
            "normalmap": "normalmapcontent", "normalmapcontent": "normalmapcontent",
            "roughnessmap": "roughnessmapcontent", "roughnessmapcontent": "roughnessmapcontent",
            "texturepack": "texturepackcontent", "texturepackcontent": "texturepackcontent",
        },
        "charactermesh": {
            "basetextureid": "basetexturecontent", "basetexturecontent": "basetexturecontent",
            "meshid": "meshcontent", "meshcontent": "meshcontent",
            "overlaytextureid": "overlaytexturecontent", "overlaytexturecontent": "overlaytexturecontent",
        },
        "hopperbin": {"textureid": "texturecontent", "texturecontent": "texturecontent"},
        "imagehandleadornment": {"image": "imagecontent", "imagecontent": "imagecontent"},
        "materialvariant": {
            "colormap": "colormapcontent", "colormapcontent": "colormapcontent",
            "metalnessmap": "metalnessmapcontent", "metalnessmapcontent": "metalnessmapcontent",
            "normalmap": "normalmapcontent", "normalmapcontent": "normalmapcontent",
            "roughnessmap": "roughnessmapcontent", "roughnessmapcontent": "roughnessmapcontent",
            "texturepack": "texturepackcontent", "texturepackcontent": "texturepackcontent",
        },
    }
    if class_key == "meshpart" and key == "textureid":
        return "texturecontent"
    if class_key == "sky":
        sky_texture_aliases = {
            "suntextureid": "suntexturecontent", "suntexturecontent": "suntexturecontent",
            "moontextureid": "moontexturecontent", "moontexturecontent": "moontexturecontent",
            "skyboxbk": "skyboxbackcontent", "skyboxbackcontent": "skyboxbackcontent",
            "skyboxdn": "skyboxdowncontent", "skyboxdowncontent": "skyboxdowncontent",
            "skyboxft": "skyboxfrontcontent", "skyboxfrontcontent": "skyboxfrontcontent",
            "skyboxlf": "skyboxleftcontent", "skyboxleftcontent": "skyboxleftcontent",
            "skyboxrt": "skyboxrightcontent", "skyboxrightcontent": "skyboxrightcontent",
            "skyboxup": "skyboxupcontent", "skyboxupcontent": "skyboxupcontent",
        }
        if key in sky_texture_aliases:
            return sky_texture_aliases[key]
    if class_key in content_property_aliases and key in content_property_aliases[class_key]:
        return content_property_aliases[class_key][key]
    if class_key == "specialmesh" and key in {"meshid", "meshcontent"}:
        return "meshcontent"
    if class_key == "meshpart" and key in {"textureid", "texturecontent"}:
        return "texturecontent"
    if class_key == "packagelink" and key in {"packageidserialize", "packagecontent"}:
        return "packagecontent"
    if class_key == "pants" and key in {"pantstemplate", "pantstemplatecontent"}:
        return "pantstemplatecontent"
    if class_key == "shirt" and key in {"shirttemplate", "shirttemplatecontent"}:
        return "shirttemplatecontent"
    if class_key == "players" and key in {"maxplayersinternal", "maxplayers"}:
        return "maxplayers"
    if class_key == "players" and key in {"preferredplayersinternal", "preferredplayers"}:
        return "preferredplayers"
    skybox_aliases = {
        "skyboxbk": "skyboxbackcontent", "skyboxbackcontent": "skyboxbackcontent",
        "skyboxdn": "skyboxdowncontent", "skyboxdowncontent": "skyboxdowncontent",
        "skyboxft": "skyboxfrontcontent", "skyboxfrontcontent": "skyboxfrontcontent",
        "skyboxlf": "skyboxleftcontent", "skyboxleftcontent": "skyboxleftcontent",
        "skyboxrt": "skyboxrightcontent", "skyboxrightcontent": "skyboxrightcontent",
        "skyboxup": "skyboxupcontent", "skyboxupcontent": "skyboxupcontent",
    }
    if class_key == "sky" and key in skybox_aliases:
        return skybox_aliases[key]
    if class_key == "starterplayer" and key in {"avatarjointupgrade_serializedrollout", "avatarjointupgrade"}:
        return "avatarjointupgrade"
    if class_key == "workspace" and key in {"signalbehavior2", "signalbehavior"}:
        return "signalbehavior"
    if class_name.casefold() in {"particleemitter", "trail", "beam", "decal", "texture"} and key in {"texture", "texturecontent"}:
        return "texturecontent"
    if key == "color3uint8":
        return "color"
    return key


def _canonical_properties(class_name, properties, side):
    result = {}
    for raw_name, value in properties.items():
        raw_key = str(raw_name).casefold()
        if raw_key == "name" or raw_key == "materialcolorsserialize":
            continue
        if raw_key == "attributesserialize" and "Attributes" in properties:
            continue
        if class_name.casefold() == "uicorner" and side == "bobux" and raw_key == "cornerradius":
            for radius in ("bottomleftradius", "bottomrightradius", "topleftradius", "toprightradius"):
                result[radius] = (str(raw_name), value)
            continue
        canonical = _canonical_property_name(class_name, str(raw_name))
        current = result.get(canonical)
        # Prefer a current Color value over its legacy BrickColor alias when
        # both are present on an instance.
        if current is None or raw_key in {"color", "color3uint8", "screeninsets"}:
            result[canonical] = (str(raw_name), value)
    return result


def compare(place_path: Path, oracle_path: Path):
    converter = load_converter()
    bobux = converter.parse_rbxl(str(place_path))
    dom_header, dom_footer, dom_instances = _read_dom_oracle(oracle_path)
    bobux_instances, bobux_by_identity, bobux_identity_by_ref = _build_bobux_identity(bobux)

    dom_by_identity = collections.defaultdict(list)
    dom_id_to_identity = {}
    for row in dom_instances:
        if row["class"] == "DataModel" and not row["identity"]:
            continue  # rbx-dom adds this synthetic root for place files.
        dom_by_identity[row["identity"]].append(row)
        dom_id_to_identity[row["id"]] = row["identity"]

    shared_keys = set(bobux_by_identity) & set(dom_by_identity)
    only_bobux = set(bobux_by_identity) - set(dom_by_identity)
    only_dom = set(dom_by_identity) - set(bobux_by_identity)
    ambiguous_bobux = sum(max(0, len(bobux_by_identity[key]) - 1) for key in bobux_by_identity)
    ambiguous_dom = sum(max(0, len(dom_by_identity[key]) - 1) for key in dom_by_identity)

    pairs = []
    paired_bobux_refs = set()
    paired_dom_ids = set()
    for identity in sorted(shared_keys):
        left_rows = bobux_by_identity[identity]
        right_rows = dom_by_identity[identity]
        if len(left_rows) == 1 and len(right_rows) == 1:
            pairs.append((identity, left_rows[0], right_rows[0], "hierarchy"))
            paired_bobux_refs.add(left_rows[0]["id"])
            paired_dom_ids.add(right_rows[0]["id"])

    # Hierarchy paths can shift when serializers reorder children. A non-zero
    # UniqueId is stable across those reorderings, so use it only as a unique,
    # class-matching fallback for the remaining rows.
    unmatched_bobux = [row for key in only_bobux for row in bobux_by_identity[key] if row["id"] not in paired_bobux_refs]
    unmatched_dom = [row for key in only_dom for row in dom_by_identity[key] if row["id"] not in paired_dom_ids]
    bobux_by_uid = collections.defaultdict(list)
    dom_by_uid = collections.defaultdict(list)
    for row in unmatched_bobux:
        uid = _unique_id_key(row["properties"], "bobux")
        if uid is not None:
            bobux_by_uid[(row["class"], uid)].append(row)
    for row in unmatched_dom:
        uid = _unique_id_key(row["properties"], "rbx_dom")
        if uid is not None:
            dom_by_uid[(row["class"], uid)].append(row)
    stable_id_matches = 0
    for uid_key in set(bobux_by_uid) & set(dom_by_uid):
        left_rows = bobux_by_uid[uid_key]
        right_rows = dom_by_uid[uid_key]
        if len(left_rows) == 1 and len(right_rows) == 1:
            left, right = left_rows[0], right_rows[0]
            pairs.append((left["identity"], left, right, "unique_id"))
            paired_bobux_refs.add(left["id"])
            paired_dom_ids.add(right["id"])
            dom_id_to_identity[right["id"]] = left["identity"]
            stable_id_matches += 1

    prop_stats = collections.Counter()
    property_buckets = collections.Counter()
    alias_matches = collections.Counter()
    mismatch_samples = []
    mismatch_sample_by_property = {}
    tag_stats = collections.Counter()
    class_counts_bobux = collections.Counter(row["class"] for row in bobux_instances)
    class_counts_dom = collections.Counter(row["class"] for row in dom_instances if not (row["class"] == "DataModel" and not row["identity"]))
    representation_stats = collections.Counter()
    sidecar_stats = collections.Counter()

    for identity, left, right, match_method in pairs:
        if match_method == "unique_id":
            prop_stats["instances_matched_by_unique_id"] += 1
        left_source_props = left["properties"]
        left_props = _canonical_properties(left["class"], left_source_props, "bobux")
        right_props = _canonical_properties(right["class"], right["properties"], "rbx_dom")
        if "MaterialColorsSerialize" in left_source_props:
            sidecar_stats["MaterialColorsSerialize"] += 1

        if "tags" in left_props or "tags" in right_props:
            tag_stats["instances_with_tags_property"] += 1
            left_tags = _canon_bobux(left_props["tags"][1], "Tags", dom_id_to_identity, bobux_identity_by_ref, left["class"]) if "tags" in left_props else None
            right_tags = _canon_dom(right_props["tags"][1], dom_id_to_identity) if "tags" in right_props else None
            if _equal(left_tags, right_tags):
                tag_stats["equal"] += 1
            else:
                tag_stats["different"] += 1
                if len(mismatch_samples) < 50:
                    mismatch_samples.append({"path": _path_text(identity), "class": left["class"], "property": "Tags", "bobux": _short(left_tags), "rbx_dom": _short(right_tags)})

        if "AttributesSerialize" in left_source_props and "attributes" in right_props:
            representation_stats["bobux_serialized_vs_rbxdom_decoded_attributes"] += 1

        common = set(left_props) & set(right_props)
        left_only = set(left_props) - set(right_props)
        right_only = set(right_props) - set(left_props)
        prop_stats["common_property_values"] += len(common)
        prop_stats["bobux_only_property_values"] += len(left_only)
        prop_stats["rbx_dom_only_property_values"] += len(right_only)
        for prop_key in left_only:
            property_buckets[f"{left['class']}.{left_props[prop_key][0]}.bobux_only"] += 1
        for prop_key in right_only:
            property_buckets[f"{right['class']}.{right_props[prop_key][0]}.rbx_dom_only"] += 1
        for prop_key in common:
            original_name = left_props[prop_key][0]
            dom_name = right_props[prop_key][0]
            if original_name.casefold() != dom_name.casefold():
                alias_matches[f"{left['class']}.{original_name} -> {dom_name}"] += 1
            left_value = _canon_bobux(left_props[prop_key][1], original_name, dom_id_to_identity, bobux_identity_by_ref, left["class"])
            right_value = _canon_dom_property(right_props[prop_key][1], original_name, dom_id_to_identity)
            if prop_key.endswith("content"):
                if left_value is None:
                    left_value = ""
                if right_value is None:
                    right_value = ""
            bucket = f"{left['class']}.{original_name}"
            if _equal(left_value, right_value):
                prop_stats["equal_values"] += 1
                property_buckets[bucket + ".equal"] += 1
            else:
                prop_stats["different_values"] += 1
                property_buckets[bucket + ".different"] += 1
                sample = {"path": _path_text(identity), "class": left["class"], "property": original_name,
                          "bobux": _short(left_value), "rbx_dom": _short(right_value)}
                mismatch_sample_by_property.setdefault(bucket, sample)
                if len(mismatch_samples) < 50:
                    mismatch_samples.append(sample)

    # Duplicate classes/names cannot always identify a unique instance when the
    # two serializers reorder indistinguishable siblings. Keep this explicit.
    report = {
        "schema": 1,
        "source": str(place_path),
        "source_bytes": place_path.stat().st_size,
        "rbx_dom": dom_header,
        "bobux": {
            "parser": "addons/rbxl_importer_v2/rbxl_converter_v2.py",
            "format": bobux.get("format"),
            "warnings": bobux.get("warnings", []),
            "property_migrations": bobux.get("property_migrations", {}),
            "instance_count": len(bobux_instances),
            "class_counts": dict(class_counts_bobux),
        },
        "instances": {
            "bobux": len(bobux_instances),
            "rbx_dom_excluding_synthetic_data_model": sum(class_counts_dom.values()),
            "matched_identity_keys": len(shared_keys),
            "only_bobux": sum(len(bobux_by_identity[key]) for key in only_bobux),
            "only_rbx_dom": sum(len(dom_by_identity[key]) for key in only_dom),
            "ambiguous_bobux_instances": ambiguous_bobux,
            "ambiguous_rbx_dom_instances": ambiguous_dom,
            "additional_matches_by_unique_id": stable_id_matches,
            "matched_instance_pairs_total": len(pairs),
            "unmatched_bobux_after_unique_id": len(bobux_instances) - len(paired_bobux_refs),
            "unmatched_rbx_dom_after_unique_id": len(dom_instances) - 1 - len(paired_dom_ids),
        },
        "unmatched_identity_samples": {
            "bobux": [
                {"path": _path_text(row["identity"]), "class": row["class"], "name": row["name"],
                 "unique_id": _unique_id_key(row["properties"], "bobux")}
                for row in unmatched_bobux if row["id"] not in paired_bobux_refs
            ][:40],
            "rbx_dom": [
                {"path": _path_text(row["identity"]), "class": row["class"], "name": row["name"],
                 "unique_id": _unique_id_key(row["properties"], "rbx_dom")}
                for row in unmatched_dom if row["id"] not in paired_dom_ids
            ][:40],
        },
        "properties": dict(prop_stats),
        "tags": dict(tag_stats),
        "representation_differences": dict(representation_stats),
        "preserved_opaque_sidecars": dict(sidecar_stats),
        "property_buckets": dict(property_buckets.most_common()),
        "top_value_mismatches": sorted(((key, count) for key, count in property_buckets.items() if key.endswith(".different")), key=lambda item: (-item[1], item[0]))[:100],
        "top_bobux_only_properties": sorted(((key, count) for key, count in property_buckets.items() if key.endswith(".bobux_only")), key=lambda item: (-item[1], item[0]))[:100],
        "top_rbx_dom_only_properties": sorted(((key, count) for key, count in property_buckets.items() if key.endswith(".rbx_dom_only")), key=lambda item: (-item[1], item[0]))[:100],
        "canonical_alias_matches": dict(alias_matches.most_common()),
        "mismatch_samples": mismatch_samples,
        "mismatch_sample_by_property": mismatch_sample_by_property,
        "rbx_dom_footer": dom_footer,
    }
    return report


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("place", type=Path)
    parser.add_argument("oracle", type=Path)
    parser.add_argument("report", type=Path)
    args = parser.parse_args(argv)
    try:
        report = compare(args.place, args.oracle)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False), encoding="utf-8")
        print(json.dumps({
            "ok": True,
            "instances": report["instances"],
            "properties": report["properties"],
            "tags": report["tags"],
            "report": str(args.report),
        }, ensure_ascii=False))
        return 0
    except Exception as error:
        print(f"comparison failed: {type(error).__name__}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
