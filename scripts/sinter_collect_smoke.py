#!/usr/bin/env python3
"""Small Sinter collect: rotated surface-code memory with Aether UF."""

from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
os.environ["PYTHONPATH"] = str(ROOT / "python") + os.pathsep + os.environ.get(
    "PYTHONPATH", ""
)

import sinter
import stim

from aether_decoders import AetherUfDecoder, ensure_release_binary


def make_circuit(distance: int, rounds: int, p: float) -> stim.Circuit:
    return stim.Circuit.generated(
        "surface_code:rotated_memory_z",
        rounds=rounds,
        distance=distance,
        after_clifford_depolarization=p,
        before_round_data_depolarization=p,
        before_measure_flip_probability=p,
        after_reset_flip_probability=p,
    )


def main() -> int:
    ensure_release_binary()
    distance, rounds, p = 3, 3, 0.01
    circ = make_circuit(distance, rounds, p)
    task = sinter.Task(
        circuit=circ,
        decoder="aether_uf",
        json_metadata={"d": distance, "r": rounds, "p": p},
    )
    stats = sinter.collect(
        num_workers=1,
        tasks=[task],
        decoders=["aether_uf"],
        custom_decoders={"aether_uf": AetherUfDecoder()},
        max_shots=200,
        max_errors=25,
        print_progress=False,
    )
    if not stats:
        print("sinter.collect returned no stats", file=sys.stderr)
        return 1
    row = stats[0]
    shots = int(row.shots)
    errors = int(row.errors)
    print("Aether Sinter collect")
    print(f"  d={distance} rounds={rounds} p={p}")
    print(f"  shots={shots} logical_errors={errors}")
    if shots == 0:
        return 1
    print(f"  logical_error_rate={errors / shots:.4g}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
