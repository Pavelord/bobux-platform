"""Extract own native Studio footage; approximate alignment, no parity claim."""

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import subprocess

DEFAULT_FFMPEG = Path(r"C:\BobuxHalloweenTrailer\tools\audio\_deps\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe")
GEOMETRIES = ("smooth_tall_block", "thin_part", "regular_parts_ladder", "single_ledge", "truss")


def hash_file(path):
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def extract(derived, video, output, ffmpeg, video_start_utc, approximate_offset_s, execute):
    data = json.loads(derived.read_text(encoding="utf-8"))
    manifest_time = dt.datetime.fromisoformat(data["date_utc"])
    video_time = dt.datetime.fromisoformat(video_start_utc)
    # ToIsoDate in native manifest has one-second precision; it is not a frame
    # synchronization marker. Root supplied an approximate measured offset.
    naive_offset = (manifest_time - video_time).total_seconds()
    tasks = []
    commands = []
    for geometry in GEOMETRIES:
        case = next(c for c in data["cases"] if c["id"] == f"r6_{geometry}_ws16_r1")
        if case["analysis_status"] != "OBSERVED":
            raise ValueError("Refuse unlabelled invalid native trial: " + case["id"])
        start = approximate_offset_s + case["begin_wall_s"] - 0.8
        # The fixed wide camera loses the head near the top of the tall ladder.
        # An earlier still documents the whole character while it is climbing.
        still_delay = 0.8 if geometry in ("regular_parts_ladder", "truss") else 1.8
        still_at = approximate_offset_s + case["begin_wall_s"] + still_delay
        clip, still = output / f"{geometry}.mp4", output / f"{geometry}.png"
        tasks.append({"geometry": geometry, "case": case["id"], "clip": str(clip.resolve()),
                      "clip_start_s": start, "clip_duration_requested_s": 8.0,
                      "still": str(still.resolve()), "still_at_s": still_at,
                      "analysis_status": case["analysis_status"],
                      "native_climbing_observed": case["climbing_observed"]})
        commands.append([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-n", "-ss", str(start),
                         "-i", str(video), "-t", "8", "-an", "-c:v", "libx264", "-threads", "1",
                         "-preset", "ultrafast", "-crf", "21", "-pix_fmt", "yuv420p", str(clip)])
        commands.append([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-n", "-ss", str(still_at),
                         "-i", str(video), "-frames:v", "1", "-threads", "1", str(still)])
    output.mkdir(parents=True, exist_ok=True)
    manifest = {"schema": 1, "status": "NATIVE_ONLY_APPROXIMATE_ALIGNMENT",
                "source_video": str(video.resolve()), "source_video_sha256": hash_file(video),
                "source_derived": str(derived.resolve()), "raw_sha256": data["raw_sha256"],
                "run_id": data["run_id"], "video_start_utc": video_start_utc,
                "run_manifest_date_utc": data["date_utc"], "naive_date_offset_s": naive_offset,
                "approximate_offset_s": approximate_offset_s,
                "alignment_uncertainty": "At least one second: wall start/ToIsoDate have no frame synchronization marker.",
                "bobux_comparison_status": "SKIP", "parity_status": "NOT_CALIBRATED",
                "commands_executed": execute, "artifacts": tasks}
    if execute:
        for command in commands:
            subprocess.run(command, check=True, capture_output=True)
        for task in tasks:
            task["clip_sha256"] = hash_file(Path(task["clip"]))
            task["still_sha256"] = hash_file(Path(task["still"]))
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("derived", type=Path)
    parser.add_argument("video", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, default=DEFAULT_FFMPEG)
    parser.add_argument("--video-start-utc", required=True)
    parser.add_argument("--approximate-offset-s", type=float, required=True)
    parser.add_argument("--execute", action="store_true", help="Default only writes a planned manifest; wait until native measurement finishes.")
    args = parser.parse_args()
    result = extract(args.derived, args.video, args.output, args.ffmpeg, args.video_start_utc,
                     args.approximate_offset_s, args.execute)
    print(json.dumps({"output": str(args.output), "status": result["status"],
                      "executed": result["commands_executed"], "artifacts": len(result["artifacts"])}))


if __name__ == "__main__":
    main()
