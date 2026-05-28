#!/usr/bin/env python3
"""Bit-identical co-sim smoke: software UF vs cycle model on Stim shots (H12).

Writes DEM JSON, samples shots, runs `decode_shots`, and a Rust unit path is
covered by `cargo test`. This script verifies the **release decode_shots**
binary against an in-process re-decode via compiling the same DEM through a
second call to decode_shots (idempotent). Primary bit-identical proof is
`assert_bit_identical` in Rust; this smoke checks Stim DEM → observables path
still works after the co-sim module landed.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import stim

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from aether_decoders.dem import dem_to_payload


def ensure_binary() -> Path:
    p = ROOT / "target" / "release" / "decode_shots"
    if not p.is_file():
        subprocess.check_call(
            ["cargo", "build", "--release", "--bin", "decode_shots"], cwd=ROOT
        )
    return p


def main() -> int:
    # Also run Rust bit-identical suite (cycle_model + blueprint cosim).
    subprocess.check_call(["cargo", "test", "--lib", "cycle_model", "--", "--nocapture"], cwd=ROOT)
    subprocess.check_call(
        ["cargo", "test", "--test", "integration_tests", "cosim_bit_identical", "--", "--nocapture"],
        cwd=ROOT,
    )

    p = 0.01
    circuit = stim.Circuit.generated(
        "surface_code:rotated_memory_z",
        distance=3,
        rounds=3,
        after_clifford_depolarization=p,
        before_round_data_depolarization=p,
        before_measure_flip_probability=p,
        after_reset_flip_probability=p,
    )
    dem = circuit.detector_error_model(decompose_errors=True)
    payload = dem_to_payload(dem)
    sampler = circuit.compile_detector_sampler(seed=1)
    shots = 32
    det, obs = sampler.sample(shots=shots, separate_observables=True)

    binary = ensure_binary()
    with tempfile.TemporaryDirectory() as td:
        dem_path = Path(td) / "dem.json"
        shots_path = Path(td) / "shots.txt"
        dem_path.write_text(json.dumps(payload))
        with shots_path.open("w") as f:
            for row in det:
                f.write("".join("1" if b else "0" for b in row) + "\n")
        out1 = subprocess.check_output([str(binary), str(dem_path), str(shots_path)], text=True)
        out2 = subprocess.check_output([str(binary), str(dem_path), str(shots_path)], text=True)

    if out1 != out2:
        print("decode_shots not deterministic across two runs", file=sys.stderr)
        return 1
    lines = [ln.strip() for ln in out1.splitlines() if ln.strip()]
    if len(lines) != shots:
        print(f"expected {shots} lines, got {len(lines)}", file=sys.stderr)
        return 1

    # Logical agreement is not required to match MWPM here; only that the UF
    # pipeline runs. Count disagreements with true obs for the log.
    disagree = sum(
        1
        for i, line in enumerate(lines)
        if [int(c) for c in line] != [int(b) for b in obs[i]]
    )
    print(
        f"cosim smoke: cargo bit-identical OK; decode_shots {shots} shots "
        f"deterministic; logical_disagree_vs_true={disagree}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
