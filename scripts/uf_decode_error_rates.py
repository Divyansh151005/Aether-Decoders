#!/usr/bin/env python3
"""Measure UF DecodeError rates (H11 gate) — phenom + circuit grids.

Default (m51): modest d∈{3,5} grid → results/uf_decode_error_m51.csv
Dense (m54): d∈{5,7} + higher p → results/uf_decode_error_m54.csv
Does not overwrite threshold_*.csv. Refs: Docs/Mwpm_Fallback_H11; Docs/Decode_Error_Rates_M*.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import stim

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from aether_decoders.dem import dem_to_payload

BIN = ROOT / "target" / "release" / "count_uf_decode_errors"


def wilson_interval(errors: int, shots: int, z: float = 1.959963984540054) -> tuple[float, float]:
    if shots <= 0:
        return (float("nan"), float("nan"))
    phat = errors / shots
    z2 = z * z
    den = 1.0 + z2 / shots
    center = (phat + z2 / (2.0 * shots)) / den
    half = z * math.sqrt((phat * (1.0 - phat) + z2 / (4.0 * shots)) / shots) / den
    return (max(0.0, center - half), min(1.0, center + half))


def make_circuit(kind: str, d: int, p: float) -> stim.Circuit:
    rounds = d
    if kind == "phenom":
        return stim.Circuit.generated(
            "surface_code:rotated_memory_z",
            distance=d,
            rounds=rounds,
            after_clifford_depolarization=0,
            before_round_data_depolarization=p,
            before_measure_flip_probability=p,
            after_reset_flip_probability=0,
        )
    if kind == "circuit":
        return stim.Circuit.generated(
            "surface_code:rotated_memory_z",
            distance=d,
            rounds=rounds,
            after_clifford_depolarization=p,
            before_round_data_depolarization=p,
            before_measure_flip_probability=p,
            after_reset_flip_probability=p,
        )
    raise ValueError(kind)


def ensure_bin() -> None:
    subprocess.check_call(
        ["cargo", "build", "--release", "--quiet", "--bin", "count_uf_decode_errors"],
        cwd=ROOT,
    )


def count_errors(dem_path: Path, shots_path: Path) -> dict:
    out = subprocess.check_output(
        [str(BIN), str(dem_path), str(shots_path)],
        cwd=ROOT,
        text=True,
    )
    return json.loads(out.strip())


def build_jobs(grid: str) -> list[tuple[str, int, float]]:
    jobs: list[tuple[str, int, float]] = []
    if grid == "m51":
        for d in (3, 5):
            for p in (0.01, 0.02, 0.03):
                jobs.append(("phenom", d, p))
        for d in (3, 5):
            for p in (0.003, 0.005, 0.01):
                jobs.append(("circuit", d, p))
    elif grid == "dense":
        # M54: d=7 + higher p (H11 stress). Do not overwrite m51 CSV.
        for d in (5, 7):
            for p in (0.03, 0.05, 0.08):
                jobs.append(("phenom", d, p))
        for d in (5, 7):
            for p in (0.01, 0.015, 0.02):
                jobs.append(("circuit", d, p))
    else:
        raise ValueError(grid)
    return jobs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--shots", type=int, default=400)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--grid", choices=("m51", "dense"), default="m51")
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--eta-sec", type=int, default=None)
    args = ap.parse_args()

    if args.out is None:
        args.out = ROOT / "results" / (
            "uf_decode_error_m51.csv" if args.grid == "m51" else "uf_decode_error_m54.csv"
        )
    if args.eta_sec is None:
        args.eta_sec = 600 if args.grid == "m51" else 3600

    jobs = build_jobs(args.grid)
    eta = args.eta_sec
    label = "M51" if args.grid == "m51" else "M54 dense"
    print(f"=== uf_decode_error_rates ({label}) ===")
    print(f"ETA ≈ {eta}s ({len(jobs)} cells × {args.shots} shots; release count bin)")
    print("Heartbeat every 15s until done.")
    t0 = time.time()
    last_hb = t0

    def maybe_hb(force: bool = False) -> None:
        nonlocal last_hb
        now = time.time()
        if force or now - last_hb >= 15:
            el = int(now - t0)
            rem = max(0, eta - el)
            print(
                f"[heartbeat] uf_decode_error_rates still running… "
                f"elapsed={el}s ETA_remaining≈{rem}s",
                flush=True,
            )
            last_hb = now

    print(f"[{time.strftime('%H:%M:%S')}] cargo build --release count_uf_decode_errors …")
    ensure_bin()
    maybe_hb(force=True)

    rows = []
    for i, (noise, d, p) in enumerate(jobs):
        maybe_hb()
        print(
            f"[{time.strftime('%H:%M:%S')}] {noise} d={d} p={p} shots={args.shots} "
            f"({i + 1}/{len(jobs)}) …",
            flush=True,
        )
        circuit = make_circuit(noise, d, p)
        dem = circuit.detector_error_model(decompose_errors=True)
        payload = dem_to_payload(dem)
        sampler = circuit.compile_detector_sampler(seed=args.seed)
        det, _ = sampler.sample(shots=args.shots, separate_observables=True)
        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            dem_path = td_path / "dem.json"
            shots_path = td_path / "shots.txt"
            dem_path.write_text(json.dumps(payload))
            with shots_path.open("w") as f:
                for row in det:
                    f.write("".join("1" if b else "0" for b in row) + "\n")
            stats = count_errors(dem_path, shots_path)
        shots = int(stats["shots"])
        ok = int(stats["ok"])
        uns = int(stats["unsolvable"])
        itl = int(stats["iter_limit"])
        abort = uns + itl
        rate = abort / shots if shots else float("nan")
        lo, hi = wilson_interval(abort, shots)
        rows.append(
            {
                "noise": noise,
                "d": d,
                "p": p,
                "shots": shots,
                "ok": ok,
                "unsolvable": uns,
                "iter_limit": itl,
                "abort": abort,
                "abort_rate": rate,
                "abort_lo": lo,
                "abort_hi": hi,
            }
        )
        print(
            f"  ok={ok} unsolvable={uns} iter_limit={itl} "
            f"abort_rate={rate:.4g} Wilson=[{lo:.4g},{hi:.4g}]",
            flush=True,
        )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "noise",
        "d",
        "p",
        "shots",
        "ok",
        "unsolvable",
        "iter_limit",
        "abort",
        "abort_rate",
        "abort_lo",
        "abort_hi",
    ]
    with args.out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    el = int(time.time() - t0)
    print(f"wrote {args.out}")
    print(f"=== DONE uf_decode_error_rates in {el}s ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
