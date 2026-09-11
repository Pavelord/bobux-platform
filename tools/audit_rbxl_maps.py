"""Parse local maps without downloading assets and report preservation counts."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import time

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("rbxl_converter", ROOT / "addons/rbxl_importer/rbxl_converter.py")
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / ".codex-tmp/studio_validation/map_audit.json")
    args = parser.parse_args()
    results, seen = [], set()
    for path in sorted(args.directory.iterdir()):
        if path.suffix.lower() not in (".rbxl", ".rbxlx"):
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        start = time.monotonic()
        try:
            value = converter.parse_rbxl(str(path))
            entries = list(value["instances"].values())
            scripts = [e for e in entries if e.get("class") in ("Script", "LocalScript", "ModuleScript")]
            row = {"file": path.name, "ok": True, "instances": len(entries),
                "scripts": len(scripts), "scripts_with_source": sum(bool(e.get("properties", {}).get("Source", "").strip()) for e in scripts),
                "warnings": value.get("warnings", []), "seconds": round(time.monotonic()-start, 2)}
        except Exception as error:
            row = {"file": path.name, "ok": False, "error": str(error)}
        results.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if results and all(r["ok"] for r in results) else 1

if __name__ == "__main__":
    raise SystemExit(main())
