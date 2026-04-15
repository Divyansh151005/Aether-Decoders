#!/usr/bin/env python3
"""Surface-code smoke: Stim DEM → Aether UF vs PyMatching logical frame."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import pymatching
import stim

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

from aether_decoders import dem_to_payload
from aether_decoders.sinter_decoder import ensure_release_binary, RELEASE_BIN


def circuit(distance: int, rounds: int, physical_p: float) -> stim.Circuit:
    return stim.Circuit.generated(
        "surface_code:rotated_memory_z",
        rounds=rounds,
        distance=distance,
        after_clifford_depolarization=physical_p,
        before_round_data_depolarization=physical_p,
        before_measure_flip_probability=physical_p,
        after_reset_flip_probability=physical_p,
    )


def pack_bits_row(bits: np.ndarray) -> str:
    return "".join("1" if b else "0" for b in bits.tolist())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--distance", type=int, default=3)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--p", type=float, default=0.001)
    parser.add_argument("--shots", type=int, default=256)
    args = parser.parse_args()

    circ = circuit(args.distance, args.rounds, args.p)
    dem = circ.detector_error_model(decompose_errors=True)
    payload = dem_to_payload(dem)

    sampler = circ.compile_detector_sampler()
    dets, obs_true = sampler.sample(shots=args.shots, separate_observables=True)
    dets = np.asarray(dets, dtype=np.uint8)
    obs_true = np.asarray(obs_true, dtype=np.uint8)

    tmp = ROOT / "target" / "stim_smoke"
    tmp.mkdir(parents=True, exist_ok=True)
    graph_path = tmp / "dem.json"
    shots_path = tmp / "shots.txt"
    graph_path.write_text(json.dumps(payload))
    shots_path.write_text("\n".join(pack_bits_row(row) for row in dets) + "\n")

    ensure_release_binary()
    proc = subprocess.run(
        [str(RELEASE_BIN), str(graph_path), str(shots_path)],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        return proc.returncode

    uf_lines = [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]
    if len(uf_lines) != args.shots:
        print(f"expected {args.shots} UF lines, got {len(uf_lines)}", file=sys.stderr)
        return 1
    uf_obs = np.array(
        [[int(c) for c in line] for line in uf_lines],
        dtype=np.uint8,
    )

    matching = pymatching.Matching.from_detector_error_model(dem)
    mwpm_obs = matching.decode_batch(dets)
    mwpm_obs = np.asarray(mwpm_obs, dtype=np.uint8)
    if mwpm_obs.ndim == 1:
        mwpm_obs = mwpm_obs.reshape(-1, 1)

    uf_err = np.any(uf_obs != obs_true, axis=1)
    mwpm_err = np.any(mwpm_obs != obs_true, axis=1)
    disagree = np.any(uf_obs != mwpm_obs, axis=1)

    print("Aether Stim smoke")
    print(f"  circuit: rotated_memory_z d={args.distance} rounds={args.rounds} p={args.p}")
    print(f"  detectors={dem.num_detectors} observables={dem.num_observables} shots={args.shots}")
    print(f"  DEM graphlike errors={len(payload['errors'])}")
    print(f"  UF logical errors:   {int(uf_err.sum())}/{args.shots}")
    print(f"  MWPM logical errors: {int(mwpm_err.sum())}/{args.shots}")
    print(f"  UF vs MWPM disagree: {int(disagree.sum())}/{args.shots}")

    if int(uf_err.sum()) > max(args.shots // 4, 1) and args.p <= 0.005:
        print("UF logical error rate is unexpectedly high for this p.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
