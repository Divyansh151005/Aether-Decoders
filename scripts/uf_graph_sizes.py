#!/usr/bin/env python3
"""Measure Union-Find decoding-graph sizes for Stim rotated_memory_z (graphlike DEM).

Used by Docs/Hardware_Mapping. Deterministic Stim circuit params; no decoder run.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

import stim

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from aether_decoders.dem import dem_to_payload


def make_circuit(distance: int, p: float, noise: str) -> stim.Circuit:
    rounds = distance
    if noise == "circuit":
        return stim.Circuit.generated(
            "surface_code:rotated_memory_z",
            rounds=rounds,
            distance=distance,
            after_clifford_depolarization=p,
            before_round_data_depolarization=p,
            before_measure_flip_probability=p,
            after_reset_flip_probability=p,
        )
    if noise == "phenom":
        return stim.Circuit.generated(
            "surface_code:rotated_memory_z",
            rounds=rounds,
            distance=distance,
            before_round_data_depolarization=p,
            before_measure_flip_probability=p,
        )
    raise ValueError(noise)


def soa_bytes(num_nodes: int, num_edges: int) -> int:
    """Conservative working-set bytes for DecoderGraph SoA (32-bit indices).

    Node: parent u32 + size u32 + parity u8 + cluster_boundary u8 + syndrome u8
          + is_boundary u8 → packed to 16 B/node.
    Edge: u u32 + v u32 + capacity u16 + growth u16 + state u8 + pad u8
          + obs_mask u64 → 24 B/edge.
    """
    return num_nodes * 16 + num_edges * 24


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--p", type=float, default=0.003)
    parser.add_argument("--distances", default="3,5,7,9,11,13,17,21")
    parser.add_argument(
        "--out",
        type=Path,
        default=ROOT / "results" / "uf_graph_sizes.csv",
    )
    args = parser.parse_args()
    distances = [int(x) for x in args.distances.split(",") if x.strip()]

    rows = []
    for noise in ("phenom", "circuit"):
        for d in distances:
            circ = make_circuit(d, args.p, noise)
            dem = circ.detector_error_model(decompose_errors=True)
            payload = dem_to_payload(dem)
            n_det = payload["num_detectors"]
            n_bnd = sum(1 for e in payload["errors"] if len(e["detectors"]) == 1)
            n_edges = sum(
                1
                for e in payload["errors"]
                if len(e["detectors"]) in (1, 2) and e["probability"] > 0
            )
            n_nodes = n_det + n_bnd
            rows.append(
                {
                    "noise": noise,
                    "d": d,
                    "p": args.p,
                    "detectors": n_det,
                    "boundaries": n_bnd,
                    "nodes": n_nodes,
                    "edges": n_edges,
                    "observables": payload["num_observables"],
                    "soa_bytes": soa_bytes(n_nodes, n_edges),
                }
            )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    print(f"wrote {args.out}")
    print(f"{'noise':8} {'d':>3} {'V':>6} {'E':>6} {'KiB':>8}")
    for r in rows:
        print(
            f"{r['noise']:8} {r['d']:>3} {r['nodes']:>6} {r['edges']:>6} "
            f"{r['soa_bytes']/1024:>8.1f}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
