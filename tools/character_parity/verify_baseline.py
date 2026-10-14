"""Check frozen evidence/protected sources without disturbing the dirty checkout."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(snapshot, allowed=()):
    baseline = json.loads((snapshot / "baseline.json").read_text(encoding="utf-8"))
    checks = []
    for relative, record in baseline["protected_files"].items():
        if relative == "**/map_format.gd":
            continue  # Initially absent; exact-name additions checked separately below.
        path = ROOT / relative
        checks.append({"name": relative, "status": "PASS" if path.is_file() and digest(path) == record["sha256"] else "FAIL"})
    # Do not scan imported assets, native dependencies, or Git internals.
    added_map_formats = [str(p.relative_to(ROOT)) for directory in ("scripts", "addons", "autoload")
                         for p in (ROOT / directory).rglob("map_format.gd")]
    checks.append({"name": "protected map_format.gd initially absent", "status": "FAIL" if added_map_formats else "PASS", "paths": added_map_formats})
    evidence = ROOT / "tests/roblox_humanoid/2026-10-13.empirical.json"
    checks.append({"name": "2026-10-13 immutable empirical SHA-256", "status": "PASS" if digest(evidence) == baseline["empirical_sha256"] else "FAIL"})
    changed = [relative for relative, record in baseline["source_files"].items()
               if not (ROOT / relative).is_file() or digest(ROOT / relative) != record["sha256"]]
    unexpected = sorted(set(changed) - set(allowed))
    checks.append({"name": "phase changes declared relative to original dirty baseline", "status": "FAIL" if unexpected else "PASS", "changed": changed, "unexpected": unexpected})
    return {"schema": 1, "baseline_head": baseline["head"], "checks": checks,
            "status": "FAIL" if any(c["status"] == "FAIL" for c in checks) else "PASS"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", type=Path)
    parser.add_argument("--allow", action="append", default=[], help="Exact reviewed source path changed in this phase")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = verify(args.snapshot, args.allow)
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")
    raise SystemExit(0 if report["status"] == "PASS" else 1)


if __name__ == "__main__":
    main()
