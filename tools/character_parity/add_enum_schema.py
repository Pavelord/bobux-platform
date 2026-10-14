"""Add one documented domain to a separate supplement at the existing pinned commit."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.request import Request, urlopen
import yaml

OUT = Path(__file__).resolve().parents[2] / "tests/roblox_humanoid/phase_a"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("domain")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", args.domain):
        raise SystemExit("Invalid enum domain name")
    primary = json.loads((OUT / "creator_docs_api.json").read_text(encoding="utf-8"))
    commit = primary["commit"]
    target = OUT / "creator_docs_enum_supplement.json"
    data = json.loads(target.read_text(encoding="utf-8")) if target.exists() else {"commit": commit, "enums": {}}
    if data["commit"] != commit or args.domain in data["enums"]:
        raise SystemExit("Supplement commit mismatch or domain already captured")
    url = f"https://raw.githubusercontent.com/Roblox/creator-docs/{commit}/content/en-us/reference/engine/enums/{args.domain}.yaml"
    with urlopen(Request(url, headers={"User-Agent": "Bobux-character-api-audit"}), timeout=30) as response:
        raw = response.read()
    schema = yaml.safe_load(raw)
    if schema["name"] != args.domain or schema["type"] != "enum":
        raise SystemExit("Unexpected official schema")
    data["enums"][args.domain] = {"source_url": url, "source_sha256": hashlib.sha256(raw).hexdigest(),
        "items": [{"name": x["name"], "value": x["value"], "tags": x.get("tags", [])} for x in schema["items"]]}
    target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Captured {args.domain} at {commit}: {len(schema['items'])} documented items")


if __name__ == "__main__":
    main()
