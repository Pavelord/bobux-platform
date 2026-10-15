"""Read-only static check of the EnumItem prototype against pinned official YAML.

This checks definition pairs, not VM behavior, ordering or production integration.
No Godot/Roblox process is started and no production source is modified.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "tests/roblox_humanoid/phase_a"
SOURCE = ROOT / "addons/roblox_runtime/enums/roblox_enum_registry.gd"


def main() -> None:
    official = json.loads((OUT / "creator_docs_api.json").read_text(encoding="utf-8"))
    supplement_path = OUT / "creator_docs_enum_supplement.json"
    if supplement_path.is_file():
        supplement = json.loads(supplement_path.read_text(encoding="utf-8"))
        if supplement["commit"] != official["commit"]:
            raise SystemExit("BLOCKED: schema supplement commit mismatch")
        official["enums"].update(supplement["enums"])
    text = SOURCE.read_text(encoding="utf-8")
    # The closing top-level brace is independent of adjacent ALIASES/SOURCES.
    # Alias names are not canonical GetEnumItems entries and are not counted.
    block = text.split("const DEFINITIONS := {", 1)[1].split("\n}\n", 1)[0]
    domains = list(re.finditer(r'(?m)^\t"([A-Za-z_][A-Za-z0-9_]*)": \[', block))
    result = {"scope": "STATIC_DEFINITION_PAIRS_ONLY; runtime/order/profile integration NOT_RUN", "official_commit": official["commit"], "registry_source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(), "domains": {}, "missing_requested_domains": sorted(set(official["enums"]) - {x.group(1) for x in domains})}
    ok = True
    for i, match in enumerate(domains):
        name = match.group(1)
        content = block[match.end():domains[i + 1].start() if i + 1 < len(domains) else len(block)]
        pairs = [(n, int(v)) for n, v in re.findall(r'\["([^"\n]+)",\s*(-?\d+)\]', content)]
        if name not in official["enums"]:
            result["domains"][name] = {"status": "BLOCKED", "reason": "official pinned domain not captured"}
            ok = False
            continue
        expected = [(x["name"], x["value"]) for x in official["enums"][name]["items"]]
        missing = sorted(set(expected) - set(pairs))
        extra = sorted(set(pairs) - set(expected))
        duplicated_names = sorted(n for n, _ in pairs if sum(1 for other, _ in pairs if other == n) > 1)
        duplicated_values = sorted(v for _, v in pairs if sum(1 for _, other in pairs if other == v) > 1)
        passed = not missing and not extra and not duplicated_names and not duplicated_values
        ok &= passed
        result["domains"][name] = {"status": "STATIC_MATCH" if passed else "STATIC_MISMATCH", "item_count": len(pairs), "missing_pairs": missing, "extra_pairs": extra, "duplicate_names": duplicated_names, "duplicate_values": duplicated_values, "same_as_yaml_sequence": pairs == expected, "sequence_is_empirically_confirmed": False}
    result["definition_pairs_ok"] = ok
    result["registered_domain_count"] = len(result["domains"])
    result["canonical_item_count"] = sum(domain.get("item_count", 0) for domain in result["domains"].values())
    result["completeness_scope"] = "Only the listed domains; a match does not establish complete Enum:GetEnums coverage. Alias behavior is checked by separate native/VM fixtures."
    (OUT / "enumitem_prototype_schema_review.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
