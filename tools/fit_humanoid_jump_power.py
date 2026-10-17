"""Fit one ballistic conversion to actual Studio JumpPower observations.

The public JumpPower stays unchanged. This is a motor approximation, not an
extracted Roblox solver formula. No failed or missing native data is invented.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math


def fit(evidence: dict) -> dict:
    assert evidence.get("source") == "roblox_studio_black_box"
    cases = [case for case in evidence["cases"] if case["status"] == "measured"
             and case["parameters"]["type"] == "jump" and case["parameters"]["UseJumpPower"]]
    if len(cases) < 6:
        raise ValueError("Six independent recorded power/gravity cases are required")
    dt = 1 / 60

    def predictions(case: dict, gain: float) -> tuple[float, float]:
        params = case["parameters"]
        velocity = params["JumpPower"] * gain
        gravity = params["gravity"]
        steps = math.floor(velocity / gravity / dt)
        height = dt * ((steps + 1) * velocity - gravity * dt * steps * (steps + 1) / 2)
        return height, velocity

    def objective(gain: float) -> float:
        total = 0.0
        for case in cases:
            height, velocity = predictions(case, gain)
            total += ((height / case["observed_apex_height"]) - 1) ** 2
            total += ((velocity / case["max_observed_vy"]) - 1) ** 2
        return total

    gain = min((1 + step / 10000 for step in range(801)), key=objective)
    return {
        "source": "engineering_fit_to_roblox_studio_black_box",
        "run_id": evidence["run_id"], "fixed_dt_seconds": dt,
        "gain": gain, "objective": objective(gain), "case_count": len(cases),
        "method": "grid least squares: relative apex and max observed velocity errors, equal weight",
        "limitations": "One R6 fixture/version at 60Hz; not an exact internal impulse formula",
        "cases": [{"name": case["name"], "parameters": case["parameters"],
                   "reference_apex": case["observed_apex_height"],
                   "reference_max_vy": case["max_observed_vy"],
                   "ballistic_height_prediction": predictions(case, gain)[0],
                   "ballistic_velocity_prediction": predictions(case, gain)[1]}
                  for case in cases],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, default=Path("tests/roblox_humanoid/2026-10-13.empirical.json"))
    parser.add_argument("--output", type=Path, default=Path(".codex-tmp/performance/humanoid-jump-power-fit.json"))
    args = parser.parse_args()
    report = fit(json.loads(args.evidence.read_text(encoding="utf-8")))
    report["evidence_sha256"] = hashlib.sha256(args.evidence.read_bytes()).hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("JumpPower fit", report["gain"], "from", report["case_count"], "recorded cases")
