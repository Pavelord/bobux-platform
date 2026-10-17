#!/usr/bin/env python3
"""Compare Roblox and Godot R6 traces by timestamp, state transitions, and ledge overhang."""

from __future__ import annotations

import argparse
import csv
import math
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Sample:
	t: float
	position: tuple[float, float, float]
	state: str
	edge_overhang: float | None


def _float(row: dict[str, str], key: str) -> float | None:
	value = row.get(key, "").strip()
	if not value:
		return None
	try:
		return float(value)
	except ValueError:
		return None


def load_trace(path: Path) -> list[Sample]:
	with path.open("r", newline="", encoding="utf-8-sig") as stream:
		reader = csv.DictReader(stream)
		rows: list[Sample] = []
		for row in reader:
			t, px, py, pz = (_float(row, key) for key in ("t", "px", "py", "pz"))
			if None in (t, px, py, pz):
				continue
			edge = _float(row, "edge_overhang_studs")
			rows.append(Sample(float(t), (float(px), float(py), float(pz)), row.get("state", "").strip(), edge))
	return sorted(rows, key=lambda sample: sample.t)


def state_transitions(samples: list[Sample]) -> list[str]:
	result: list[str] = []
	for sample in samples:
		if sample.state and (not result or result[-1] != sample.state):
			result.append(sample.state)
	return result


def interpolate(samples: list[Sample], t: float) -> tuple[float, float, float]:
	if t <= samples[0].t:
		return samples[0].position
	if t >= samples[-1].t:
		return samples[-1].position
	low = 0
	high = len(samples) - 1
	while high - low > 1:
		middle = (low + high) // 2
		if samples[middle].t <= t:
			low = middle
		else:
			high = middle
	a, b = samples[low], samples[high]
	span = b.t - a.t
	alpha = (t - a.t) / span if span > 0.0 else 0.0
	return tuple(a.position[axis] + (b.position[axis] - a.position[axis]) * alpha for axis in range(3))


def aligned_error(studio: list[Sample], godot: list[Sample]) -> tuple[float, list[tuple[float, float]]]:
	start = max(studio[0].t, godot[0].t)
	end = min(studio[-1].t, godot[-1].t)
	if end < start:
		return math.inf, []
	times = sorted({start, end, *(s.t for s in studio if start <= s.t <= end), *(s.t for s in godot if start <= s.t <= end)})
	errors: list[tuple[float, float]] = []
	for t in times:
		a = interpolate(studio, t)
		b = interpolate(godot, t)
		errors.append((t, math.dist(a, b)))
	return max((error for _, error in errors), default=math.inf), errors


def first_fall_overhang(samples: list[Sample]) -> float | None:
	previous = ""
	for sample in samples:
		if sample.state in {"Freefall", "FallingDown"} and previous not in {"Freefall", "FallingDown"}:
			if sample.edge_overhang is not None:
				return sample.edge_overhang
		previous = sample.state
	return None


def write_svg(path: Path, title: str, series: list[tuple[float, float]]) -> None:
	width, height = 1100, 520
	left, top, plot_w, plot_h = 78, 66, 970, 380
	max_t = max((t for t, _ in series), default=1.0)
	max_error = max((error for _, error in series), default=0.1)
	max_error = max(max_error * 1.12, 0.11)
	points = []
	for t, error in series:
		x = left + plot_w * t / max(max_t, 1e-9)
		y = top + plot_h * (1.0 - error / max_error)
		points.append(f"{x:.2f},{y:.2f}")
	path_data = "M " + " L ".join(points) if points else ""
	limit_y = top + plot_h * (1.0 - min(0.1 / max_error, 1.0))
	content = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<rect width="100%" height="100%" fill="#ffffff"/>
<text x="{left}" y="32" font-family="sans-serif" font-size="22" fill="#17202a">{title}</text>
<line x1="{left}" y1="{top}" x2="{left}" y2="{top+plot_h}" stroke="#536273"/>
<line x1="{left}" y1="{top+plot_h}" x2="{left+plot_w}" y2="{top+plot_h}" stroke="#536273"/>
<line x1="{left}" y1="{limit_y:.2f}" x2="{left+plot_w}" y2="{limit_y:.2f}" stroke="#d35400" stroke-dasharray="7 6"/>
<path d="{path_data}" fill="none" stroke="#2471a3" stroke-width="2"/>
<text x="{left}" y="{top+plot_h+30}" font-family="sans-serif" font-size="14">0 s</text>
<text x="{left+plot_w-55}" y="{top+plot_h+30}" font-family="sans-serif" font-size="14">{max_t:.2f} s</text>
<text x="18" y="{top+plot_h/2}" transform="rotate(-90 18 {top+plot_h/2})" font-family="sans-serif" font-size="15">position error (studs)</text>
<text x="{left+plot_w-200}" y="{limit_y-8:.2f}" font-family="sans-serif" font-size="13" fill="#d35400">0.1 stud acceptance limit</text>
</svg>'''
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(content, encoding="utf-8")


def compare_scenario(name: str, studio_path: Path, godot_path: Path, report_dir: Path) -> dict[str, str]:
	if not studio_path.exists() or not godot_path.exists():
		return {"scenario": name, "status": "MISSING", "max_position_error": "", "states_match": "", "edge_overhang_error": ""}
	studio, godot = load_trace(studio_path), load_trace(godot_path)
	if len(studio) < 2 or len(godot) < 2:
		return {"scenario": name, "status": "FAIL", "max_position_error": "insufficient samples", "states_match": "NO", "edge_overhang_error": ""}
	max_error, series = aligned_error(studio, godot)
	state_match = state_transitions(studio) == state_transitions(godot)
	studio_edge, godot_edge = first_fall_overhang(studio), first_fall_overhang(godot)
	edge_error: float | None = None
	if studio_edge is not None and godot_edge is not None:
		edge_error = abs(studio_edge - godot_edge)
	edge_required = name.startswith("walk_edge") or name.startswith("walk_corner")
	edge_match = not edge_required or (edge_error is not None and edge_error < 0.05)
	passed = max_error < 0.1 and state_match and edge_match
	write_svg(report_dir / f"{name}.svg", f"{name}: maximum position error {max_error:.4f} stud", series)
	return {
		"scenario": name,
		"status": "PASS" if passed else "FAIL",
		"max_position_error": f"{max_error:.6f}",
		"states_match": "YES" if state_match else "NO",
		"edge_overhang_error": "" if edge_error is None else f"{edge_error:.6f}",
	}


def main() -> None:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--studio", type=Path, default=Path("tests/roblox_traces/roblox"))
	parser.add_argument("--godot", type=Path, default=Path("tests/roblox_traces/godot"))
	parser.add_argument("--report", type=Path, default=Path("tests/roblox_traces/reports"))
	args = parser.parse_args()
	names = sorted({path.stem for path in args.studio.glob("*.csv")} | {path.stem for path in args.godot.glob("*.csv")})
	rows = [compare_scenario(name, args.studio / f"{name}.csv", args.godot / f"{name}.csv", args.report) for name in names]
	args.report.mkdir(parents=True, exist_ok=True)
	with (args.report / "summary.csv").open("w", newline="", encoding="utf-8") as stream:
		writer = csv.DictWriter(stream, fieldnames=["scenario", "status", "max_position_error", "states_match", "edge_overhang_error"])
		writer.writeheader()
		writer.writerows(rows)
	print(f"{'Scenario':32} {'Result':8} {'Max position (stud)':22} {'States':8} {'Edge overhang error'}")
	for row in rows:
		print(f"{row['scenario']:32} {row['status']:8} {row['max_position_error']:22} {row['states_match']:8} {row['edge_overhang_error']}")
	print(f"Reports: {args.report}")


if __name__ == "__main__":
	main()
