#!/usr/bin/env python3
"""Extract tagged R6 CSV rows from a copied Roblox Studio Output log."""

from __future__ import annotations

import argparse
import csv
import io
import re
from pathlib import Path


def parse_fields(line: str) -> list[str]:
	return next(csv.reader([line], skipinitialspace=False))


def write_rows(path: Path, header: list[str], rows: list[list[str]], time_column: int | None = None) -> None:
	path.parent.mkdir(parents=True, exist_ok=True)
	with path.open("w", newline="", encoding="utf-8") as stream:
		writer = csv.writer(stream)
		writer.writerow(header)
		base_time = float(rows[0][time_column]) if rows and time_column is not None else 0.0
		for row in rows:
			if time_column is not None:
				row = list(row)
				row[time_column] = f"{float(row[time_column]) - base_time:.9f}"
			writer.writerow(row)


def collect(source: Path, output: Path) -> tuple[int, int, int]:
	trace_header: list[str] | None = None
	part_header: list[str] | None = None
	trace_rows: dict[str, list[list[str]]] = {}
	part_rows: list[list[str]] = []
	sensor_rows: list[list[str]] = []
	metadata: list[str] = []
	sensor_header: list[str] | None = None

	for raw_line in source.read_text(encoding="utf-8", errors="replace").splitlines():
		for marker in ("R6TRACE_COLUMNS,", "R6TRACE,", "R6PART_COLUMNS,", "R6PART,", "R6PART_META,", "R6SENSOR_COLUMNS,", "R6SENSOR,"):
			index = raw_line.find(marker)
			if index < 0:
				continue
			fields = parse_fields(raw_line[index:])
			if marker == "R6TRACE_COLUMNS,":
				trace_header = fields[1:]
			elif marker == "R6TRACE,":
				if len(fields) >= 3:
					trace_rows.setdefault(fields[1], []).append(fields[2:])
			elif marker == "R6PART_COLUMNS,":
				part_header = fields[1:]
			elif marker == "R6PART,":
				part_rows.append(fields[1:])
			elif marker == "R6PART_META,":
				metadata.append(",".join(fields[1:]))
			elif marker == "R6SENSOR_COLUMNS,":
				sensor_header = fields[1:]
			elif marker == "R6SENSOR,":
				sensor_rows.append(fields[1:])
			break

	if trace_header is not None:
		for scenario, rows in trace_rows.items():
			safe_name = re.sub(r"[^A-Za-z0-9_.-]+", "_", scenario)
			write_rows(output / "roblox" / f"{safe_name}.csv", trace_header[1:], rows, time_column=0)
	if part_header is not None and part_rows:
		write_rows(output / "part_dump.csv", part_header, part_rows)
	if metadata:
		(output / "part_dump_meta.txt").write_text("\n".join(metadata) + "\n", encoding="utf-8")
	if sensor_header is not None and sensor_rows:
		write_rows(output / "sensor_logger.csv", sensor_header, sensor_rows)
	return len(trace_rows), len(part_rows), len(sensor_rows)


def main() -> None:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("studio_output", type=Path, help="Text file copied from Roblox Studio Output")
	parser.add_argument("--out", type=Path, default=Path("tests/roblox_traces"), help="Output trace directory")
	args = parser.parse_args()
	trace_count, part_count, sensor_count = collect(args.studio_output, args.out)
	print(f"Collected {trace_count} scenarios, {part_count} R6 parts, and {sensor_count} sensor samples into {args.out}")
	if trace_count == 0:
		print("No R6TRACE rows found. Check that the trace LocalScript ran while R6Scenario was set.")


if __name__ == "__main__":
	main()
