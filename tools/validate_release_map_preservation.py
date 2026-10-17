"""Record or compare published mode data without modifying maps or accounts."""
import argparse
import hashlib
import json
import pathlib
import urllib.parse
import urllib.request

MAPS = {
    "park": "akx0oto939gi501_bobux_park_krut",
    "valley": "akx0oto939gi501_dolina_semi_vetrov",
    "nds": "z9ovqynlv860sgw_narural disaster survival - bobux edition",
    "lift": "evd29np4936q499_normalnyi_lift",
    "city_rp": "evd29np4936q499_бобукс сити рп",
}

def identity(data):
    if isinstance(data, str):
        data = json.loads(data)
    encoded = json.dumps(data, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    sources = set()
    def walk(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key.lower() in {"source", "code", "lua_source", "original_source"} and isinstance(child, str) and child.strip():
                    sources.add(hashlib.sha256(child.encode("utf-8")).hexdigest())
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)
    walk(data)
    return {"sha256": hashlib.sha256(encoded).hexdigest(), "script_sha256": sorted(sources)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["snapshot", "compare"])
    parser.add_argument("path", type=pathlib.Path)
    parser.add_argument("--base", default="http://109.71.245.162/api/rest/v1")
    args = parser.parse_args()
    result = {}
    for key, map_id in MAPS.items():
        query = urllib.parse.urlencode({"id": "eq." + map_id, "select": "id,data", "limit": 1})
        request = urllib.request.Request(args.base + "/maps?" + query, headers={"apikey": "bobux-public-vps"})
        with urllib.request.urlopen(request, timeout=90) as response:
            rows = json.load(response)
        if len(rows) != 1 or rows[0]["id"] != map_id:
            raise RuntimeError("Published map unavailable: " + key)
        data = rows[0]["data"]
        if isinstance(data, str):
            data = json.loads(data)
        external = data.get("__bobux_external_map_data_url") if isinstance(data, dict) else None
        if external:
            if urllib.parse.urlparse(external).netloc != urllib.parse.urlparse(args.base).netloc:
                raise RuntimeError("External map is outside the verified Bobux host")
            with urllib.request.urlopen(external, timeout=90) as response:
                raw = response.read()
            expected = data.get("__bobux_external_map_data_sha256")
            if expected and hashlib.sha256(raw).hexdigest().lower() != expected.lower():
                raise RuntimeError("Published map file checksum mismatch: " + key)
            data = json.loads(raw)
        result[key] = {"id": map_id, **identity(data)}
        print("[map-preservation]", key, result[key]["sha256"], "scripts=", len(result[key]["script_sha256"]), flush=True)
    if args.action == "snapshot":
        args.path.parent.mkdir(parents=True, exist_ok=True)
        args.path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    elif result != json.loads(args.path.read_text(encoding="utf-8")):
        raise RuntimeError("Published map data changed since the release snapshot")
    print("[map-preservation] PASS", args.action)

if __name__ == "__main__":
    main()
