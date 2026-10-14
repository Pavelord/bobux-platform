"""Phase A1 audit only: official API schema and static source-corpus evidence.

No game code is changed and no map script is executed. Member-name matches are
lexical candidates, never proof of receiver type, execution or compatibility.
"""
from __future__ import annotations

import concurrent.futures
import hashlib
import json
import mmap
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

import yaml

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "tests/roblox_humanoid/phase_a"
BASE_CLASSES = "Humanoid HumanoidDescription Animator AnimationTrack Animation AnimationController Seat VehicleSeat Tool Accessory TrussPart SpawnLocation ForceField Player Players StarterPlayer Workspace PathfindingService UserInputService ContextActionService BasePart Motor6D Attachment ControllerManager ControllerPartSensor GroundController AirController ClimbController SwimController Constraint WeldConstraint NoCollisionConstraint Camera Path".split()
ENUM_DOMAINS = "HumanoidStateType HumanoidRigType AnimationPriority CameraType CameraMode Material CoreGuiType SensorMode SensorUpdateType".split()


def member_name(name: str) -> str:
    return re.split(r"[.:]", name, maxsplit=1)[-1]


def fetch(url: str) -> bytes:
    with urlopen(Request(url, headers={"User-Agent": "Bobux-character-api-audit"}), timeout=45) as response:
        return response.read()


def sha_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def schema(commit: str | None = None) -> dict:
    commit = commit or json.loads(fetch("https://api.github.com/repos/Roblox/creator-docs/commits/main"))["sha"]
    result = {"source": "Roblox/creator-docs", "commit": commit, "fetched_utc": datetime.now(timezone.utc).isoformat(), "classes": {}}
    pending = set(BASE_CLASSES)
    while pending:
        current = sorted(pending)
        pending.clear()
        def one(name: str) -> tuple[str, dict]:
            url = f"https://raw.githubusercontent.com/Roblox/creator-docs/{commit}/content/en-us/reference/engine/classes/{name}.yaml"
            raw = fetch(url)
            data = yaml.safe_load(raw)
            normalized = {"source_url": url, "source_sha256": hashlib.sha256(raw).hexdigest(), "inherits": data.get("inherits", []), "descendants": data.get("descendants", []), "tags": data.get("tags", []), "members": [], "nonpublic": []}
            for kind in ("properties", "methods", "events", "callbacks"):
                for member in data.get(kind, []) or []:
                    security = member.get("security", "None")
                    public = any(str(v) == "None" for v in security.values()) if isinstance(security, dict) else str(security) == "None"
                    entry = {"name": member["name"], "kind": kind, "type": member.get("type"), "parameters": member.get("parameters", []), "returns": member.get("returns", []), "tags": member.get("tags", []), "security": security}
                    # Keep factual signatures; avoid copying prose/code from docs.
                    entry["parameters"] = [{k: v for k, v in p.items() if k != "summary"} for p in entry["parameters"]]
                    entry["returns"] = [{k: v for k, v in p.items() if k != "summary"} for p in entry["returns"]]
                    normalized["members" if public else "nonpublic"].append(entry)
            return name, normalized
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            for name, value in pool.map(one, current):
                result["classes"][name] = value
                pending.update(p for p in value["inherits"] if p not in result["classes"] and p not in current)
                if name == "Constraint" or name.endswith("Constraint"):
                    pending.update(p for p in value["descendants"] if p not in result["classes"] and p not in current)
    OUT.mkdir(parents=True, exist_ok=True)
    result["enums"] = {}
    for name in ENUM_DOMAINS:
        url = f"https://raw.githubusercontent.com/Roblox/creator-docs/{commit}/content/en-us/reference/engine/enums/{name}.yaml"
        raw = fetch(url)
        data = yaml.safe_load(raw)
        result["enums"][name] = {"source_url": url, "source_sha256": hashlib.sha256(raw).hexdigest(), "items": [{"name": item["name"], "value": item["value"], "tags": item.get("tags", [])} for item in data.get("items", [])]}
    (OUT / "creator_docs_api.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return result


STRING = re.compile(rb'"Source"\s*:\s*("(?:[^"\\]|\\.)*")')
MEMBER = re.compile(r'[.:]\s*([A-Za-z_][A-Za-z0-9_]*)\b')
# This deliberately does not try to parse or type-check Luau.
COMMENT = re.compile(r'--\[\[.*?\]\]|--[^\n]*', re.S)


def map_corpus(api: dict) -> dict:
    historical = ROOT / ".codex-tmp/attached_map_audit_20261003/source_parse_report.json"
    maps = json.loads(historical.read_text(encoding="utf-8"))
    names = {member_name(m["name"]) for c in api["classes"].values() for m in c["members"]}
    output = {"schema_version": 1, "method": "Static .member/:member lexical candidates from decoded Source. Receiver type and execution are not inferred; strings may match. Each source counts once per member. No gameplay executed.", "historical_manifest": str(historical.relative_to(ROOT)).replace("\\", "/"), "historical_manifest_sha256": sha_file(historical), "maps": [], "member_candidates": defaultdict(list)}
    enum_output = {"schema_version": 1, "method": "Regex candidates after removing ordinary line and --[[ ]] comments; not Luau AST or data-flow. Receiver type unverified; strings can match. Source ordinals refer to Source fields in the corpus JSON.", "maps": [], "categories": {}}
    enum_patterns = {
        "get_state_direct_numeric_compare": r"GetState\s*\([^)]*\)\s*(?:==|~=|<=|>=|<|>)\s*\d+",
        "get_state_reverse_numeric_compare": r"\d+\s*(?:==|~=|<=|>=|<|>)\s*[^\n;=]*?GetState\s*\([^)]*\)",
        "camera_type_numeric": r"\.CameraType\s*(?:==|~=|=)\s*\d+",
        "material_numeric": r"\.Material\s*(?:==|~=|=)\s*\d+",
        "animation_priority_numeric": r"\.Priority\s*(?:==|~=|=)\s*\d+",
        "change_state_numeric": r"(?:ChangeState|SetStateEnabled|GetStateEnabled)\s*\(\s*\d+",
        "enum_item_field": r"Enum\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.(?:Name|Value|EnumType)\b",
        "enum_typeof": r"typeof\s*\(\s*Enum\.",
        "enum_tostring": r"tostring\s*\(\s*Enum\.",
        "enum_items": r"\b(?:GetEnumItems|GetEnums)\s*\(",
        "enum_material": r"\bEnum\.Material\.[A-Za-z_][A-Za-z0-9_]*",
        "enum_humanoid_state": r"\bEnum\.HumanoidStateType\.[A-Za-z_][A-Za-z0-9_]*",
        "enum_camera_type": r"\bEnum\.CameraType\.[A-Za-z_][A-Za-z0-9_]*",
        "enum_animation_priority": r"\bEnum\.AnimationPriority\.[A-Za-z_][A-Za-z0-9_]*",
        "enum_core_gui_type": r"\bEnum\.CoreGuiType\.[A-Za-z_][A-Za-z0-9_]*",
    }
    compiled = {k: re.compile(v) for k, v in enum_patterns.items()}
    for item in maps:
        path = ROOT / item["json"]
        source = Path("C:/Users/Pavel/Downloads") / item["file"]
        entry = {"index": item["index"], "file": item["file"], "original_exists_now": source.is_file(), "original_sha256_recorded": item["sha256"], "corpus_json": str(path.relative_to(ROOT)).replace("\\", "/"), "corpus_exists_now": path.is_file(), "historical_scripts_total": item["scripts"], "historical_scripts_with_source": item.get("scripts_with_source"), "sources_scanned": 0, "nonempty_sources": 0, "member_candidates": {}}
        if source.is_file():
            entry["original_sha256_now"] = sha_file(source)
            entry["original_matches_historical"] = entry["original_sha256_now"] == item["sha256"]
        counter = Counter()
        enum_entry = {"index": item["index"], "file": item["file"], "categories": {}}
        enum_counts = Counter()
        enum_examples = defaultdict(list)
        if path.is_file():
            entry["corpus_json_sha256"] = sha_file(path)
            with path.open("rb") as handle, mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ) as view:
                for match in STRING.finditer(view):
                    text = json.loads(match.group(1))
                    entry["sources_scanned"] += 1
                    entry["nonempty_sources"] += bool(text)
                    cleaned = COMMENT.sub("", text)
                    counter.update(set(MEMBER.findall(cleaned)) & names)
                    for category, pattern in compiled.items():
                        for hit in pattern.finditer(cleaned):
                            enum_counts[category] += 1
                            if len(enum_examples[category]) < 8:
                                line = cleaned.count("\n", 0, hit.start()) + 1
                                enum_examples[category].append({"source_ordinal": entry["sources_scanned"], "line_in_comment_stripped_source": line, "match": hit.group(0)[:180]})
        entry["member_candidates"] = dict(sorted(counter.items()))
        enum_entry["categories"] = {k: {"matches": n, "examples": enum_examples[k]} for k, n in enum_counts.items()}
        enum_entry["corpus_json_sha256"] = entry.get("corpus_json_sha256")
        enum_output["maps"].append(enum_entry)
        output["maps"].append(entry)
        for member, count in counter.items():
            output["member_candidates"][member].append({"map_index": item["index"], "source_count": count})
        print(f"map {item['index']:02}: {entry['sources_scanned']} Source fields; original matches={entry.get('original_matches_historical')}", flush=True)
    output["member_candidates"] = dict(sorted(output["member_candidates"].items()))
    (OUT / "map_api_candidates.json").write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    enum_output["categories"] = {k: {"regex": v, "matches": sum(m["categories"].get(k, {}).get("matches", 0) for m in enum_output["maps"]), "maps": [m["index"] for m in enum_output["maps"] if k in m["categories"]]} for k, v in enum_patterns.items()}
    (OUT / "map_enum_candidates.json").write_text(json.dumps(enum_output, ensure_ascii=False, indent=2), encoding="utf-8")
    return output


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--refresh-docs", action="store_true", help="Refresh pinned official schema; otherwise reuse exact existing snapshot")
    args = parser.parse_args()
    cache = OUT / "creator_docs_api.json"
    api = schema() if args.refresh_docs or not cache.exists() else json.loads(cache.read_text(encoding="utf-8"))
    if not set(BASE_CLASSES).issubset(api["classes"]) or not set(ENUM_DOMAINS).issubset(api.get("enums", {})):
        api = schema(api["commit"])
    corpus = map_corpus(api)
    print(json.dumps({"classes": len(api["classes"]), "declared_public_members": sum(len(x["members"]) for x in api["classes"].values()), "maps": len(corpus["maps"]), "sources": sum(x["sources_scanned"] for x in corpus["maps"])}))
