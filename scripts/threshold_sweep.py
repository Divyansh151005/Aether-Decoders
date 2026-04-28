#!/usr/bin/env python3
"""Sinter threshold sweep: Aether UF vs PyMatching on rotated surface-code memory."""

from __future__ import annotations

import argparse
import csv
import math
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
    raise ValueError(f"unknown noise model {noise!r}")


def wilson_interval(errors: int, shots: int, z: float = 1.959963984540054) -> tuple[float, float]:
    """Wilson score 95% CI for a binomial proportion. Closed form; no extra deps."""
    if shots <= 0:
        return (float("nan"), float("nan"))
    phat = errors / shots
    z2 = z * z
    den = 1.0 + z2 / shots
    center = (phat + z2 / (2.0 * shots)) / den
    half = z * math.sqrt((phat * (1.0 - phat) + z2 / (4.0 * shots)) / shots) / den
    return (max(0.0, center - half), min(1.0, center + half))


def write_tables(stats: list[sinter.TaskStats], csv_path: Path) -> None:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "noise",
        "decoder",
        "d",
        "p",
        "shots",
        "errors",
        "ler",
        "ler_lo",
        "ler_hi",
    ]
    rows = []
    for st in stats:
        meta = st.json_metadata or {}
        shots = int(st.shots)
        errors = int(st.errors)
        ler = (errors / shots) if shots else float("nan")
        lo, hi = wilson_interval(errors, shots)
        rows.append(
            {
                "noise": meta.get("noise", ""),
                "decoder": st.decoder,
                "d": meta.get("d", ""),
                "p": meta.get("p", ""),
                "shots": shots,
                "errors": errors,
                "ler": ler,
                "ler_lo": lo,
                "ler_hi": hi,
            }
        )
    rows.sort(key=lambda r: (str(r["noise"]), int(r["d"]), float(r["p"]), str(r["decoder"])))
    with csv_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"wrote {csv_path}")
    print(
        f"{'noise':8} {'d':>3} {'p':>8} {'decoder':12} "
        f"{'shots':>7} {'err':>5} {'LER':>10} {'95% Wilson':>22}"
    )
    for r in rows:
        ler = r["ler"]
        ler_s = f"{ler:.4g}" if isinstance(ler, float) else str(ler)
        ci_s = f"[{r['ler_lo']:.4g}, {r['ler_hi']:.4g}]"
        print(
            f"{r['noise']:8} {r['d']:>3} {r['p']:>8} {r['decoder']:12} "
            f"{r['shots']:>7} {r['errors']:>5} {ler_s:>10} {ci_s:>22}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--noise", choices=("circuit", "phenom", "both"), default="circuit")
    parser.add_argument("--distances", default="3,5")
    parser.add_argument("--ps", default="")
    parser.add_argument("--max-shots", type=int, default=1500)
    parser.add_argument(
        "--max-errors",
        type=int,
        default=1_000_000_000,
        help="Sinter error cap. Use a huge value so LER rows share the same shot count.",
    )
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--progress", action="store_true")
    parser.add_argument(
        "--out",
        type=Path,
        default=ROOT / "results" / "threshold_sweep.csv",
    )
    args = parser.parse_args()

    distances = [int(x) for x in args.distances.split(",") if x.strip()]
    if args.ps:
        ps = [float(x) for x in args.ps.split(",") if x.strip()]
    else:
        ps = [0.003, 0.006, 0.01, 0.015]
    noises = ["circuit", "phenom"] if args.noise == "both" else [args.noise]

    ensure_release_binary()
    tasks = []
    for noise in noises:
        for d in distances:
            for p in ps:
                circ = make_circuit(d, p, noise)
                tasks.append(
                    sinter.Task(
                        circuit=circ,
                        json_metadata={"d": d, "r": d, "p": p, "noise": noise},
                    )
                )

    stats = sinter.collect(
        num_workers=max(1, args.workers),
        tasks=tasks,
        decoders=["aether_uf", "pymatching"],
        custom_decoders={"aether_uf": AetherUfDecoder()},
        max_shots=args.max_shots,
        max_errors=args.max_errors,
        print_progress=args.progress,
    )
    if not stats:
        print("sinter.collect returned no stats", file=sys.stderr)
        return 1
    write_tables(stats, args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
