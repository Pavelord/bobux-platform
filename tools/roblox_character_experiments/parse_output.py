"""Parse only our markers, validate exports, retain raw facts without parity claims."""
import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import json
from pathlib import Path
import statistics

from marker_bytes import marker_payload, read_marker_bytes

PREFIX = "CHARACTER_EXPERIMENT_JSON "
EXPORT = "CHARACTER_EXPORT_SMALL "
EXPORT_DONE = "CHARACTER_EXPORT_SMALL_DONE "
METADATA = "CHARACTER_METADATA_EXPORT "
METADATA_DONE = "CHARACTER_METADATA_DONE "


def read_input_bytes(data, metadata_only=False):
    markers = (METADATA, METADATA_DONE) if metadata_only else (PREFIX, EXPORT, EXPORT_DONE)
    return read_marker_bytes(data, markers)


def decode_marker(line, marker):
    payload = marker_payload(line, marker)
    if payload is None:
        return None
    return json.loads(payload)


def reconstruct(text, run_id=None):
    packets = defaultdict(dict)
    manifests = {}
    issues = []
    for line_number, line in enumerate(text.splitlines(), 1):
        try:
            done = decode_marker(line, EXPORT_DONE)
            if done:
                manifests[done["run_id"]] = done
                continue
            packet = decode_marker(line, EXPORT)
            if not packet:
                continue
            key = (packet["run_id"], packet["n"])
            offset = int(packet["i"])
            prior = packets[key].get(offset)
            if prior is not None and prior != packet["s"]:
                issues.append(f"conflicting duplicate packet {key} offset {offset}")
            packets[key][offset] = packet["s"]
        except (ValueError, KeyError, TypeError) as exc:
            issues.append(f"malformed export line {line_number}: {exc}")
    if not packets:
        # Direct raw file produced by reconstruct is also an accepted input.
        raw = "\n".join(PREFIX + payload for line in text.splitlines() if (payload := marker_payload(line, PREFIX)) is not None) + "\n"
        if not raw.strip():
            issues.append("no full raw data/export markers")
        return raw, None, issues
    runs = sorted({key[0] for key in packets})
    if run_id is None:
        if len(runs) != 1:
            return "", None, issues + [f"multiple exported runs {runs}; specify --run-id"]
        run_id = runs[0]
    chunks = []
    for key in sorted(k for k in packets if k[0] == run_id):
        expected = 1
        values = []
        for offset, value in sorted(packets[key].items()):
            if offset != expected:
                issues.append(f"missing/overlapping packet in {key}: expected {expected}, received {offset}")
            values.append(value)
            # Luau string.sub offsets are UTF-8 byte positions, not Python characters.
            expected = offset + len(value.encode("utf-8"))
        chunks.append("".join(values))
    raw = "".join(chunks)
    manifest = manifests.get(run_id)
    if manifest is None:
        issues.append(f"export completion marker missing for {run_id}")
    elif len(raw.encode("utf-8")) != manifest["bytes"]:
        issues.append(f"raw bytes mismatch: reconstructed {len(raw.encode('utf-8'))}, advertised {manifest['bytes']}")
    return raw, manifest, issues


def parse_raw(raw):
    rows, issues = [], []
    for line_number, line in enumerate(raw.splitlines(), 1):
        if not line.startswith(PREFIX):
            issues.append(f"non-probe line in raw data {line_number}")
            continue
        try:
            value = json.loads(line[len(PREFIX):])
            if not isinstance(value, dict):
                issues.append(f"raw JSON record is not an object at line {line_number}")
                continue
            rows.append(value)
        except json.JSONDecodeError as exc:
            issues.append(f"malformed JSON line {line_number}: {exc}")
    if rows:
        expected = 1
        run = rows[0].get("run_id")
        for row in rows:
            if row.get("seq") != expected:
                issues.append(f"sequence gap: expected {expected}, found {row.get('seq')}")
            if row.get("run_id") != run:
                issues.append("mixed run IDs in raw data")
            expected += 1
    return rows, issues


def distribution(values):
    values = [v for v in values if isinstance(v, (int, float))]
    if not values:
        return None
    return dict(n=len(values), median=statistics.median(values), min=min(values), max=max(values))


def report(rows, raw, issues):
    manifests = [r for r in rows if r.get("kind") == "run_manifest"]
    manifest = manifests[-1] if manifests else {}
    cases = [r for r in rows if r.get("kind") == "case_result"]
    last = next((r for r in reversed(rows) if r.get("kind") == "run_result"), None)
    if not last:
        issues.append("run_result missing; run incomplete")
    groups = defaultdict(list)
    for case in cases:
        params = case.get("parameters", {})
        groups[(params.get("geometry"), params.get("WalkSpeed"), params.get("rig"))].append(case)
    summaries = []
    for key, trials in sorted(groups.items()):
        outcomes = Counter(str(t.get("climbing")) for t in trials)
        item = dict(geometry=key[0], WalkSpeed=key[1], rig=key[2], completed_trials=len(trials),
                    statuses=dict(Counter(t["status"] for t in trials)), climb_outcomes=dict(outcomes),
                    vertical_speed=distribution([t.get("vertical_speed_median") for t in trials]),
                    max_root_rise=distribution([t.get("max_root_rise") for t in trials]),
                    holdout_ids=[t["case"] for t in trials if t.get("parameters", {}).get("split") == "holdout"],
                    train_ids=[t["case"] for t in trials if t.get("parameters", {}).get("split") == "train"])
        if len(trials) < 5:
            item["calibration_status"] = "BLOCKED: fewer than five completed trials"
        elif len(outcomes) > 1:
            item["calibration_status"] = "BLOCKED: noisy discrete climbing outcome; separately preregister ten-repeat extension"
        else:
            item["calibration_status"] = "OBSERVED_BASELINE_ONLY: no Bobux implementation comparison"
        summaries.append(item)
    fresh = [r for r in rows if r.get("kind") == "server_record" and r.get("server", {}).get("kind") == "a2_fresh_humanoid"]
    official = [r["server"] for r in rows if r.get("kind") == "server_record" and r.get("server", {}).get("kind") == "a2_official_model"]
    native = [r for r in rows if r.get("kind") == "a2_native_getters"]
    return dict(schema=1, run_id=manifest.get("run_id"), studio_version=manifest.get("studio_version"),
                date_utc=manifest.get("date_utc"), mode=manifest.get("mode"), raw_sha256=hashlib.sha256(raw.encode("utf-8")).hexdigest(),
                raw_records=len(rows), parser_issues=issues, status="BLOCKED" if issues or not last or last.get("status") == "BLOCKED" else "OBSERVED",
                parity_status="NOT_IMPLEMENTED_NOT_CALIBRATED", units=manifest.get("units"), run_result=last,
                baseline_summary=summaries, a2_counts=dict(fresh_instances=len(fresh), official_models=dict(Counter(r["rig"] for r in official)),
                native_getter_observations=dict(Counter(r["rig"] + "_" + r["profile"] for r in native))),
                source_provenance="Real official Studio public APIs; raw output is immutable evidence once saved; no original assets/source exported")


def parse_metadata(text):
    chunks, completions = {}, {}
    total_bytes = 0
    limit = 16 * 1024 * 1024
    for line_number, line in enumerate(text.splitlines(), 1):
        done = decode_marker(line, METADATA_DONE)
        if done is not None:
            if not isinstance(done, dict) or not isinstance(done.get("run_id"), str) or not 0 < len(done["run_id"]) <= 64:
                raise ValueError(f"invalid metadata DONE run_id at line {line_number}")
            if done["run_id"] in completions and completions[done["run_id"]] != done:
                raise ValueError("conflicting metadata completion")
            completions[done["run_id"]] = done
            continue
        packet = decode_marker(line, METADATA)
        if packet is None:
            continue
        if not isinstance(packet, dict) or not isinstance(packet.get("n"), str) or not packet["n"].isdigit():
            raise ValueError(f"invalid metadata offset at line {line_number}")
        offset = int(packet["n"])
        value = packet.get("s")
        if packet["n"] != f"{offset:06d}" or not 1 <= offset <= limit or not isinstance(value, str):
            raise ValueError(f"invalid metadata packet at line {line_number}")
        size = len(value.encode("utf-8"))
        if not 0 < size <= 400:
            raise ValueError("metadata segment byte size outside 1..400")
        if offset in chunks and chunks[offset] != value:
            raise ValueError("conflicting metadata packet; split captures before parsing")
        if offset not in chunks:
            total_bytes += size
            if total_bytes > limit:
                raise ValueError("metadata exceeds 16 MiB cap")
        chunks[offset] = value
    if not chunks and not completions:
        return None
    if len(completions) != 1:
        raise ValueError("expected one metadata DONE; legacy packets are not bound to runs")
    done = next(iter(completions.values()))
    if type(done.get("bytes")) is not int or not 0 < done["bytes"] <= limit:
        raise ValueError("invalid metadata DONE byte count")
    if type(done.get("rows")) is not int or not 0 <= done["rows"] <= 10000:
        raise ValueError("invalid metadata DONE row count")
    expected = 1
    segments = []
    for offset, value in sorted(chunks.items()):
        if offset != expected:
            raise ValueError(f"metadata segment gap/overlap: expected byte {expected}, received {offset}")
        segments.append(value)
        expected += len(value.encode("utf-8"))
    raw = "".join(segments)
    if len(raw.encode("utf-8")) != done["bytes"]:
        raise ValueError("metadata DONE byte count mismatch")
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get("kind") != "a4_standard_script_metadata" or data.get("schema") not in (1, 2):
        raise ValueError("unknown/missing metadata schema")
    if data.get("run_id") != done["run_id"]:
        raise ValueError("metadata payload/DONE run_id mismatch")
    if not isinstance(data.get("scripts"), list) or len(data["scripts"]) != done["rows"]:
        raise ValueError("metadata payload/DONE row count mismatch")
    if data.get("rig") != done.get("rig"):
        raise ValueError("metadata payload/DONE rig mismatch")
    return data


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("input", type=Path)
    p.add_argument("--output", type=Path, required=True, help="output stem, without suffix")
    p.add_argument("--run-id")
    p.add_argument("--metadata-only", action="store_true")
    args = p.parse_args()
    text, encoding_issues = read_input_bytes(args.input.read_bytes(), args.metadata_only)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.metadata_only:
        if encoding_issues:
            raise SystemExit("BLOCKED: " + "; ".join(encoding_issues))
        try:
            data = parse_metadata(text)
        except (ValueError, TypeError, KeyError) as exc:
            raise SystemExit("BLOCKED metadata integrity: " + str(exc)) from exc
        if data is None:
            raise SystemExit("BLOCKED: no metadata export")
        path = args.output.with_suffix(".metadata.json")
        if path.exists():
            raise SystemExit("Refusing to overwrite metadata evidence; select a fresh --output stem")
        with path.open("x", encoding="utf-8") as stream:
            stream.write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        print(f"metadata: {len(data['scripts'])} source-derived inventory rows; no source retained")
        return
    raw, manifest, issues = reconstruct(text, args.run_id)
    issues = encoding_issues + issues
    rows, problems = parse_raw(raw)
    issues.extend(problems)
    if manifest and manifest["records"] != len(rows):
        issues.append(f"record count mismatch: advertised {manifest['records']}, reconstructed {len(rows)}")
    data = report(rows, raw, issues)
    args.output.with_suffix(".raw.log").write_text(raw, encoding="utf-8", newline="")
    args.output.with_suffix(".observed.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    with args.output.with_suffix(".frames.csv").open("w", encoding="utf-8", newline="") as f:
        columns = ["seq", "case", "frame", "sim_s", "wall_s", "phase", "dt_sim_s", "state", "x", "y", "z", "vx", "vy", "vz"]
        writer = csv.DictWriter(f, columns)
        writer.writeheader()
        for row in rows:
            if row.get("kind") != "frame":
                continue
            out = {k: row.get(k) for k in columns[:8]}
            out.update(state=row["state"]["Name"])
            out.update(zip(columns[9:12], row["position"]))
            out.update(zip(columns[12:15], row["linear_velocity"]))
            writer.writerow(out)
    print(json.dumps({k: data[k] for k in ["run_id", "mode", "status", "raw_sha256", "raw_records", "parser_issues", "a2_counts"]}, indent=2))
    raise SystemExit(0 if data["status"] == "OBSERVED" else 2)


if __name__ == "__main__":
    main()
