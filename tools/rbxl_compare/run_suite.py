#!/usr/bin/env python3
"""Run Bobux V2 vs rbx-dom structural and property comparisons for a fixed map set."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from datetime import datetime

from xml_compat import is_legacy_xml, sanitize_legacy_xml

HERE = Path(__file__).resolve().parent
COMPARE_ONE = HERE / "compare_one.py"
DEFAULT_MAP_LIST = HERE / "attached_maps_2026-10-03.txt"


def _sha256(path: Path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _report_one(name: str, index: int, total: int, source: Path, oracle_exe: Path, output_dir: Path, reuse_oracle=False, expected_sha256=None):
    oracle_path = output_dir / "oracle" / f"{index:02d}_{source.stem}.rbxdom.jsonl.gz"
    diff_path = output_dir / "diff" / f"{index:02d}_{source.stem}.diff.json"
    oracle_path.parent.mkdir(parents=True, exist_ok=True)
    diff_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    record = {
        "name": name,
        "source": str(source),
        "source_bytes": source.stat().st_size,
        "sha256": _sha256(source),
        "oracle_dump": str(oracle_path),
        "diff_report": str(diff_path),
    }

    if reuse_oracle and oracle_path.is_file() and expected_sha256 == record["sha256"]:
        oracle = subprocess.CompletedProcess([str(oracle_exe), str(source), str(oracle_path)], 0, "", "")
        record["rbx_dom_oracle_reused"] = True
    else:
        oracle = subprocess.run(
            [str(oracle_exe), str(source), str(oracle_path)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if oracle.returncode != 0 and is_legacy_xml(source):
            sanitized_path = output_dir / "sanitized_xml" / f"{index:02d}_{source.name}"
            record["oracle_xml_sanitization"] = sanitize_legacy_xml(source, sanitized_path)
            oracle = subprocess.run(
                [str(oracle_exe), str(sanitized_path), str(oracle_path)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            record["oracle_sanitized_input"] = str(sanitized_path)
    record["rbx_dom_exit_code"] = oracle.returncode
    if oracle.stdout.strip():
        record["rbx_dom_stdout"] = oracle.stdout.strip()[-4000:]
    if oracle.stderr.strip():
        record["rbx_dom_stderr"] = oracle.stderr.strip()[-12000:]
    if oracle.returncode != 0:
        record["status"] = "rbx_dom_failed"
        record["elapsed_seconds"] = round(time.monotonic() - started, 3)
        return record

    compare = subprocess.run(
        [sys.executable, str(COMPARE_ONE), str(source), str(oracle_path), str(diff_path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    record["bobux_compare_exit_code"] = compare.returncode
    if compare.stdout.strip():
        record["compare_stdout"] = compare.stdout.strip()[-4000:]
    if compare.stderr.strip():
        record["compare_stderr"] = compare.stderr.strip()[-12000:]
    if compare.returncode != 0:
        record["status"] = "bobux_compare_failed"
    else:
        try:
            report = json.loads(diff_path.read_text(encoding="utf-8"))
            record["status"] = "ok"
            record["format"] = report["bobux"].get("format")
            record["property_migrations"] = report["bobux"].get("property_migrations", {})
            record["instances"] = report["instances"]
            record["properties"] = report["properties"]
            record["tags"] = report["tags"]
            record["representation_differences"] = report["representation_differences"]
            record["preserved_opaque_sidecars"] = report["preserved_opaque_sidecars"]
            record["top_value_mismatches"] = report["top_value_mismatches"][:20]
            record["top_bobux_only_properties"] = report["top_bobux_only_properties"][:20]
            record["top_rbx_dom_only_properties"] = report["top_rbx_dom_only_properties"][:20]
            record["canonical_alias_matches"] = report["canonical_alias_matches"]
            record["bobux_warnings"] = report["bobux"].get("warnings", [])[:80]
        except Exception as error:
            record["status"] = "report_read_failed"
            record["report_error"] = f"{type(error).__name__}: {error}"
    record["elapsed_seconds"] = round(time.monotonic() - started, 3)
    return record


def _render_markdown(summary):
    lines = [
        "# Bobux V2 vs rbx-dom place diff",
        "",
        f"Generated: {summary['generated_local']}",
        f"Oracle: {summary['oracle'].get('name', 'rojo-rbx/rbx-dom')} ({summary['oracle'].get('rbx_binary', 'unknown')}, {summary['oracle'].get('rbx_xml', 'unknown')}, {summary['oracle'].get('rbx_dom_weak', 'unknown')})",
        f"Source directory: `{summary['input_dir']}`",
        f"Maps in manifest: {summary['manifest_count']}",
        "",
        "`rbx-dom` inserts one synthetic DataModel root; counts below exclude that root. Property aliases are normalized through explicit reflection migrations noted in each JSON report.",
        "",
        "| Map | Status | Instances Bobux / rbx-dom | Matched | Tag mismatches | Property equal / different | Bobux only / rbx-dom only | Migrated fields | sec |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in summary["maps"]:
        instances = row.get("instances", {})
        props = row.get("properties", {})
        tags = row.get("tags", {})
        migration_count = sum((row.get("property_migrations") or {}).values())
        lines.append(
            "| {name} | {status} | {bi} / {di} | {matched} | {tagdiff} | {equal} / {different} | {bonly} / {donly} | {migrations} | {elapsed} |".format(
                name=row["name"].replace("|", "\\|"),
                status=row["status"],
                bi=instances.get("bobux", "—"),
                di=instances.get("rbx_dom_excluding_synthetic_data_model", "—"),
                matched=instances.get("matched_identity_keys", "—"),
                tagdiff=tags.get("different", 0),
                equal=props.get("equal_values", "—"),
                different=props.get("different_values", 0),
                bonly=props.get("bobux_only_property_values", "—"),
                donly=props.get("rbx_dom_only_property_values", "—"),
                migrations=migration_count,
                elapsed=row.get("elapsed_seconds", "—"),
            )
        )
    lines.extend(["", "## Files", ""])
    lines.append("- Full JSON/NDJSON reports are under `oracle/` and `diff/` next to this summary.")
    lines.append("- Maps with errors record the parser return code and bounded error output in `summary.json`.")
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True, type=Path)
    parser.add_argument("--oracle-exe", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--maps-file", type=Path, default=DEFAULT_MAP_LIST)
    parser.add_argument("--only", action="append", default=[], help="Only process a filename from the manifest; repeatable")
    parser.add_argument("--reuse-oracle", action="store_true", help="Reuse existing oracle dumps and rerun only Bobux comparisons")
    parser.add_argument("--refresh-oracle", action="store_true", help="Regenerate oracle dumps even when cached dumps are valid")
    parser.add_argument("--merge-summary", action="store_true", help="Merge selected map results into an existing full summary")
    args = parser.parse_args(argv)

    manifest_names = [line.strip() for line in args.maps_file.read_text(encoding="utf-8").splitlines() if line.strip() and not line.lstrip().startswith("#")]
    manifest_indices = {name: index for index, name in enumerate(manifest_names, 1)}
    names = list(manifest_names)
    if args.only:
        requested = set(args.only)
        unknown = requested - set(names)
        if unknown:
            parser.error("--only contains names missing from the manifest: " + ", ".join(sorted(unknown)))
        names = [name for name in names if name in requested]
    args.output_dir.mkdir(parents=True, exist_ok=True)
    old_summary_path = args.output_dir / "summary.json"
    prior_hashes = {}
    prior_summary = None
    if args.reuse_oracle and old_summary_path.is_file():
        try:
            prior_summary = json.loads(old_summary_path.read_text(encoding="utf-8"))
            prior_hashes = {row["name"]: row.get("sha256") for row in prior_summary.get("maps", []) if row.get("sha256")}
        except (OSError, ValueError, KeyError, TypeError):
            prior_hashes = {}
    if args.merge_summary and old_summary_path.is_file() and prior_summary is None:
        try:
            prior_summary = json.loads(old_summary_path.read_text(encoding="utf-8"))
        except (OSError, ValueError, TypeError):
            prior_summary = None
    rows = []
    oracle_info = {"name": "rojo-rbx/rbx-dom", "rbx_binary": "unknown", "rbx_xml": "unknown", "rbx_dom_weak": "unknown"}
    for selected_index, name in enumerate(names, 1):
        index = manifest_indices[name]
        source = args.input_dir / name
        if not source.is_file():
            row = {"name": name, "source": str(source), "status": "source_missing", "elapsed_seconds": 0}
        else:
            row = _report_one(name, index, len(manifest_names), source, args.oracle_exe, args.output_dir,
                              args.reuse_oracle and not args.refresh_oracle, prior_hashes.get(name))
        rows.append(row)
        if row.get("status") == "ok" and oracle_info.get("rbx_binary") == "unknown":
            oracle_report = json.loads(Path(row["diff_report"]).read_text(encoding="utf-8"))["rbx_dom"]
            oracle_info = {"name": "rojo-rbx/rbx-dom", **{
                key: json.loads(Path(row["diff_report"]).read_text(encoding="utf-8"))["rbx_dom"].get(key)
                for key in ("parser", "rbx_binary", "rbx_xml", "rbx_dom_weak")
            }}
        print(json.dumps({
            "progress": f"{selected_index}/{len(names)}",
            "map": name,
            "status": row["status"],
            "elapsed_seconds": row.get("elapsed_seconds", 0),
            "instances": row.get("instances"),
            "property_differences": (row.get("properties") or {}).get("different_values"),
        }, ensure_ascii=False), flush=True)

    if args.merge_summary and prior_summary:
        merged_by_name = {row["name"]: row for row in prior_summary.get("maps", [])}
        merged_by_name.update({row["name"]: row for row in rows})
        rows = [merged_by_name[name] for name in manifest_names if name in merged_by_name]
    summary = {
        "schema": 1,
        "generated_local": datetime.now().astimezone().isoformat(timespec="seconds"),
        "input_dir": str(args.input_dir.resolve()),
        "manifest": str(args.maps_file.resolve()),
        "manifest_count": len(manifest_names),
        "selected_count": len(names),
        "oracle": oracle_info,
        "maps": rows,
    }
    summary_path = args.output_dir / "summary.json"
    markdown_path = args.output_dir / "summary.md"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    markdown_path.write_text(_render_markdown(summary), encoding="utf-8")
    print(json.dumps({"complete": True, "summary": str(summary_path), "markdown": str(markdown_path), "map_count": len(rows)}, ensure_ascii=False))
    return 0 if all(row["status"] == "ok" for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
