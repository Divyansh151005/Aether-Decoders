#!/usr/bin/env python3
"""Stim-compiled UF → software cosim gate + Icarus/Verilator grow/peel harness.

Default phenom d=5 r=5 (M23). Circuit d=3 r=3 needs peel MAX_DEG≥63 (M24).
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import stim

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from aether_decoders.dem import dem_to_payload


def make_circuit(kind: str, d: int, rounds: int, p: float) -> stim.Circuit:
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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--kind", choices=("phenom", "circuit"), default="phenom")
    ap.add_argument("--distance", type=int, default=5)
    ap.add_argument("--rounds", type=int, default=5)
    ap.add_argument("--p", type=float, default=0.02)
    ap.add_argument("--shots", type=int, default=24)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--rtl-cases", type=int, default=2)
    ap.add_argument("--skip-icarus", action="store_true")
    ap.add_argument(
        "--sim",
        choices=("iverilog", "verilator"),
        default="iverilog",
        help="RTL simulator (verilator installed for M23 large graphs)",
    )
    args = ap.parse_args()

    subprocess.check_call(["cargo", "test", "--quiet"], cwd=ROOT)

    circuit = make_circuit(args.kind, args.distance, args.rounds, args.p)
    dem = circuit.detector_error_model(decompose_errors=True)
    payload = dem_to_payload(dem)
    sampler = circuit.compile_detector_sampler(seed=args.seed)
    det, _obs = sampler.sample(shots=args.shots, separate_observables=True)

    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        dem_path = td_path / "dem.json"
        shots_path = td_path / "shots.txt"
        dem_path.write_text(json.dumps(payload))
        with shots_path.open("w") as f:
            for row in det:
                f.write("".join("1" if b else "0" for b in row) + "\n")

        out_sv = ROOT / "rtl" / "gen" / "stim_cases.sv"
        cmd = [
            "cargo",
            "run",
            "--quiet",
            "--bin",
            "gen_stim_rtl_vectors",
            "--",
            str(dem_path),
            str(shots_path),
            str(out_sv),
            str(args.rtl_cases),
        ]
        subprocess.check_call(cmd, cwd=ROOT)

    if args.skip_icarus:
        print("skip RTL sim")
        return 0

    rtl = ROOT / "rtl"
    if args.sim == "iverilog":
        sim = rtl / "tb_stim_sim"
        subprocess.check_call(
            [
                "iverilog",
                "-g2012",
                "-o",
                str(sim),
                "aether_uf_grow_merge.sv",
                "aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv",
                "tb_aether_uf_stim.sv",
            ],
            cwd=rtl,
        )
        subprocess.check_call([str(sim)], cwd=rtl)
    else:
        # Verilator: binary TB (timing). Unpacked array ports need -Wno-UNOPTFLAT etc.
        subprocess.check_call(
            [
                "verilator",
                "--binary",
                "-j",
                "0",
                "-Wall",
                "-Wno-fatal",
                "--timing",
                "--top-module",
                "tb_aether_uf_stim",
                "-o",
                "tb_stim_verilator",
                "aether_uf_grow_merge.sv",
                "aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv",
                "tb_aether_uf_stim.sv",
            ],
            cwd=rtl,
        )
        subprocess.check_call([str(rtl / "obj_dir" / "tb_stim_verilator")], cwd=rtl)

    # Blueprint regression
    subprocess.check_call(["cargo", "run", "--quiet", "--bin", "gen_rtl_vectors"], cwd=ROOT)
    subprocess.check_call(
        [
            "iverilog",
            "-g2012",
            "-o",
            "tb_decode_sim",
            "aether_uf_grow_merge.sv",
            "aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv",
            "tb_aether_uf_decode.sv",
        ],
        cwd=rtl,
    )
    subprocess.check_call([str(rtl / "tb_decode_sim")], cwd=rtl)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
