"""Decode own character Enum observations; no namespace/parity completeness claim."""
import argparse
import hashlib
import json
from pathlib import Path

from parse_humanoid_edges import decode

EXPORT = "CHARACTER_ENUM_EXPORT "
DONE = "CHARACTER_ENUM_DONE "
DOMAINS = {"HumanoidStateType", "HumanoidRigType", "AnimationPriority", "CameraType", "CameraMode",
           "Material", "CoreGuiType", "SensorMode", "SensorUpdateType", "RaycastFilterType"}


def report(raw, done, issues):
    issues = list(issues)
    try:
        payload = json.loads(raw.decode("utf-8", errors="strict"))
        if not isinstance(payload, dict):
            raise ValueError("raw root must be an object")
    except (ValueError, UnicodeError) as exc:
        payload = {}
        issues.append(f"invalid own UTF-8/JSON: {exc}")
    if payload.get("schema") != 1 or payload.get("kind") != "character_enum_domains":
        issues.append("unknown raw schema")
    if payload.get("no_expected_outcomes") is not True:
        issues.append("observation-only provenance missing")
    families = payload.get("families", [])
    if not isinstance(families, list):
        families = []
        issues.append("families must be a list")
    names, item_count, summaries = set(), 0, []
    for seq, family in enumerate(families, 1):
        if not isinstance(family, dict):
            issues.append(f"family {seq} must be an object")
            continue
        name, values = family.get("name"), family.get("items", [])
        if not isinstance(name, str):
            issues.append(f"family {seq} name must be a string")
            continue
        if name in names or name not in DOMAINS or family.get("seq") != seq:
            issues.append(f"family {seq} unknown/duplicate name or wrong sequence")
        names.add(name)
        if family.get("status") != "OBSERVED" or not isinstance(values, list):
            issues.append(f"family {seq} incomplete")
            values = []
        if family.get("item_count") != len(values):
            issues.append(f"family {seq} item count mismatch")
        item_names, item_values, pairs = set(), set(), []
        for order, value in enumerate(values, 1):
            if not isinstance(value, dict):
                issues.append(f"family {seq} item {order} must be an object")
                continue
            label, number = value.get("Name"), value.get("Value")
            if not isinstance(label, str) or type(number) is not int:
                issues.append(f"family {seq} item {order} has invalid name/value types")
                continue
            if (not isinstance(label, str) or not label or type(number) is not int or
                    label in item_names or number in item_values or value.get("order") != order):
                issues.append(f"family {seq} item {order} invalid identity/order")
            item_names.add(label)
            item_values.add(number)
            pairs.append([label, number])
        item_count += len(values)
        summaries.append({"name": name, "canonical_items_in_native_order": pairs,
                          "identity_equal": all(value.get("identity_equal") is True for value in values),
                          "family_identity": all(value.get("family_identity") is True for value in values)})
    if names != DOMAINS:
        issues.append("ten requested domains are incomplete/extra")
    aliases = payload.get("aliases", [])
    if not isinstance(aliases, list):
        aliases = []
    alias_ids = {(a.get("domain"), a.get("alias")) for a in aliases if isinstance(a, dict)
                 and isinstance(a.get("domain"), str) and isinstance(a.get("alias"), str)}
    if alias_ids != {
            ("RaycastFilterType", "Blacklist"), ("RaycastFilterType", "Whitelist")} or len(aliases) != 2:
        issues.append("alias observation coverage mismatch")
    if payload.get("domain_count") != len(families) or payload.get("canonical_item_count") != item_count:
        issues.append("raw aggregate count mismatch")
    if done:
        for field in ("run_id", "date_utc", "studio_version", "status", "domain_count", "canonical_item_count", "alias_count", "blocked_domains"):
            if done.get(field) != payload.get(field):
                issues.append(f"payload/DONE {field} mismatch")
    if not payload.get("date_utc") or not payload.get("studio_version"):
        issues.append("UTC/version provenance missing")
    if payload.get("blocked_domains") != 0 or payload.get("status") != "OBSERVED":
        issues.append("native domains contain blocked observations")
    return {"schema": 1, "status": "BLOCKED" if issues else "OBSERVED", "parser_issues": issues,
            "run_id": payload.get("run_id"), "studio_version": payload.get("studio_version"),
            "date_utc": payload.get("date_utc"), "raw_sha256": hashlib.sha256(raw).hexdigest(),
            "domain_count": len(families), "canonical_item_count": item_count,
            "domains": summaries, "root": payload.get("root"), "aliases": aliases,
            "parity_status": "NOT_IMPLEMENTED_NOT_CALIBRATED",
            "scope": "Ten public character enum domains; root count is not full native item coverage"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--run-id")
    args = parser.parse_args()
    paths = [args.output.with_suffix(s) for s in (".export.log", ".raw.json", ".observed.json")]
    if any(path.exists() for path in paths):
        raise SystemExit("Refusing to overwrite evidence; select a fresh stem")
    if args.input.stat().st_size > 128 * 1024 * 1024:
        raise SystemExit("Native log exceeds size cap")
    raw, done, issues, retained = decode(args.input.read_bytes(), args.run_id, export_marker=EXPORT, done_marker=DONE)
    result = report(raw, done, issues)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with paths[0].open("x", encoding="utf-8", newline="") as stream:
        stream.write("\n".join(retained) + "\n")
    with paths[1].open("xb") as stream:
        stream.write(raw)
    with paths[2].open("x", encoding="utf-8") as stream:
        stream.write(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("status", "parser_issues", "run_id", "raw_sha256", "domain_count", "canonical_item_count")}))
    raise SystemExit(0 if result["status"] == "OBSERVED" else 2)


if __name__ == "__main__":
    main()
