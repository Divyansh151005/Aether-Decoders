#!/usr/bin/env python3
"""Smoke: Relay-BP on Stim color_code DEM (hyperedges; not graphlike UF)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import stim

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

from aether_decoders.dem_relay import dem_to_relay_payload


def ensure_relay_binary() -> Path:
    bin_path = ROOT / "target" / "release" / "decode_relay_shots"
    if not bin_path.is_file():
        subprocess.check_call(
            ["cargo", "build", "--release", "--bin", "decode_relay_shots"],
            cwd=ROOT,
        )
    return bin_path


def main() -> int:
    p = 0.001
    circuit = stim.Circuit.generated(
        "color_code:memory_xyz",
        distance=3,
        rounds=3,
        after_clifford_depolarization=p,
        before_round_data_depolarization=p,
        before_measure_flip_probability=p,
        after_reset_flip_probability=p,
    )
    dem = circuit.detector_error_model(decompose_errors=False)
    payload = dem_to_relay_payload(
        dem,
        relay={
            "stop_nconv": 1,
            "num_sets": 20,
            "pre_iter": 40,
            "set_max_iter": 40,
            "gamma0": 0.125,
            "gamma_lo": -0.24,
            "gamma_hi": 0.66,
            "seed": 1,
        },
    )
    # Confirm hyperedges exist (UF cannot compile these).
    max_deg = max((len(e["detectors"]) for e in payload["errors"]), default=0)
    print(f"DEM: detectors={dem.num_detectors} observables={dem.num_observables} "
          f"errors={len(payload['errors'])} max_col_weight={max_deg}")
    if max_deg <= 2:
        print("warning: expected hyperedges on color_code; max degree <= 2", file=sys.stderr)

    sampler = circuit.compile_detector_sampler()
    shots = 64
    det, obs = sampler.sample(shots=shots, separate_observables=True)

    binary = ensure_relay_binary()
    with tempfile.TemporaryDirectory() as td:
        dem_path = Path(td) / "dem.json"
        shots_path = Path(td) / "shots.txt"
        dem_path.write_text(json.dumps(payload))
        with shots_path.open("w") as f:
            for row in det:
                f.write("".join("1" if b else "0" for b in row) + "\n")
        proc = subprocess.run(
            [str(binary), str(dem_path), str(shots_path)],
            capture_output=True,
            text=True,
            check=True,
        )

    pred_lines = [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]
    if len(pred_lines) != shots:
        print(f"expected {shots} output lines, got {len(pred_lines)}", file=sys.stderr)
        return 1

    logical_errors = 0
    for i, line in enumerate(pred_lines):
        pred = [int(c) for c in line]
        true = [int(b) for b in obs[i]]
        if pred != true:
            logical_errors += 1

    print(f"shots={shots} logical_errors={logical_errors} "
          f"LER={logical_errors / shots:.4g}")
    print("relay_bp color_code smoke OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
