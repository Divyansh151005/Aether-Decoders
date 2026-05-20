#!/usr/bin/env python3
"""Matched-shot bake-off: Aether Relay-BP vs BP+OSD on a published BB Stim circuit.

Circuit source: IBM trmue/relay testdata (Apache-2.0), bivariate bicycle memory_Z.
Reference decoder: ldpc.BpOsdDecoder with OSD-CS order 10 (Müller et al. comparison setup).
Relay hyperparameters: Müller et al. gross-code defaults (γ₀=0.125, γ∈[-0.24,0.66]).
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

import numpy as np
import stim
from ldpc.bposd_decoder import BpOsdDecoder

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

from aether_decoders.dem_relay import dem_to_relay_payload

TESTDATA = ROOT / "testdata" / "bicycle_bivariate"

# Prior OSD pace @ p≈0.005 on [[144,12,12]] (M27/M29 measured ~15–40 s/shot; use mid).
_PRIOR_OSD_SEC_PER_SHOT = 22.0
_HEARTBEAT_SEC = 15.0


class Heartbeat:
    """Print a line every `interval` seconds so long jobs are visibly alive."""

    def __init__(self, label: str, *, interval: float = _HEARTBEAT_SEC) -> None:
        self.label = label
        self.interval = interval
        self._stop = threading.Event()
        self._t0 = time.time()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def _run(self) -> None:
        while not self._stop.wait(self.interval):
            elapsed = time.time() - self._t0
            print(
                f"  [heartbeat] {self.label} still running… "
                f"elapsed={elapsed:.0f}s ({elapsed / 60:.1f} min)",
                flush=True,
            )

    def __enter__(self) -> Heartbeat:
        self._t0 = time.time()
        self._thread.start()
        return self

    def __exit__(self, *args: object) -> None:
        self._stop.set()
        self._thread.join(timeout=1.0)


def fmt_duration(seconds: float) -> str:
    if not math.isfinite(seconds) or seconds < 0:
        return "?"
    if seconds < 90:
        return f"{seconds:.0f}s"
    return f"{seconds / 60:.1f} min"


def wilson_interval(errors: int, shots: int, z: float = 1.959963984540054) -> tuple[float, float]:
    if shots <= 0:
        return (float("nan"), float("nan"))
    if errors == 0:
        # Exact: lower = 0; upper = z²/(n+z²) form of Wilson at phat=0
        return (0.0, (z * z) / (shots + z * z))
    if errors == shots:
        return (shots / (shots + z * z), 1.0)
    phat = errors / shots
    z2 = z * z
    den = 1.0 + z2 / shots
    center = (phat + z2 / (2.0 * shots)) / den
    half = z * math.sqrt((phat * (1.0 - phat) + z2 / (4.0 * shots)) / shots) / den
    return (max(0.0, center - half), min(1.0, center + half))


def ensure_relay_binary() -> Path:
    bin_path = ROOT / "target" / "release" / "decode_relay_shots"
    if not bin_path.is_file():
        subprocess.check_call(
            ["cargo", "build", "--release", "--bin", "decode_relay_shots"],
            cwd=ROOT,
        )
    return bin_path


def dem_matrices(dem: stim.DetectorErrorModel) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """H (M×N), A (K×N), priors (N,) from undecomposed DEM — same columns as Relay payload."""
    payload = dem_to_relay_payload(dem)
    m = payload["num_detectors"]
    k = payload["num_observables"]
    n = len(payload["errors"])
    h = np.zeros((m, n), dtype=np.uint8)
    a = np.zeros((k, n), dtype=np.uint8)
    priors = np.zeros(n, dtype=np.float64)
    for j, err in enumerate(payload["errors"]):
        priors[j] = err["probability"]
        for d in err["detectors"]:
            h[d, j] ^= 1
        for o in err["observables"]:
            a[o, j] ^= 1
    return h, a, priors


def resolve_circuit(name: str, p: float) -> Path:
    p_str = f"{p:.6f}".rstrip("0").rstrip(".")
    candidates = sorted(TESTDATA.glob(f"circuit={name},*error_rate={p_str},*.stim"))
    if not candidates:
        raise FileNotFoundError(
            f"No circuit for {name} p={p} under {TESTDATA}. "
            "Download from https://github.com/trmue/relay/tree/main/tests/testdata/bicycle_bivariate"
        )
    if len(candidates) > 1:
        raise RuntimeError(f"ambiguous circuits: {[c.name for c in candidates]}")
    return candidates[0]


def decode_relay(
    binary: Path,
    payload: dict,
    det: np.ndarray,
) -> np.ndarray:
    """Return (shots, num_obs) predicted observables."""
    n = len(det)
    print(
        f"  aether_relay: decoding {n} shots (batch subprocess; "
        f"heartbeat every {_HEARTBEAT_SEC:.0f}s until done)",
        flush=True,
    )
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        dem_path = td_path / "dem.json"
        shots_path = td_path / "shots.txt"
        dem_path.write_text(json.dumps(payload))
        with shots_path.open("w") as f:
            for row in det:
                f.write("".join("1" if b else "0" for b in row) + "\n")
        t0 = time.time()
        with Heartbeat(f"aether_relay ({n} shots)"):
            proc = subprocess.run(
                [str(binary), str(dem_path), str(shots_path)],
                capture_output=True,
                text=True,
                check=True,
            )
        print(
            f"  aether_relay: finished in {fmt_duration(time.time() - t0)}",
            flush=True,
        )
    lines = [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]
    if len(lines) != len(det):
        raise RuntimeError(f"relay returned {len(lines)} lines for {len(det)} shots")
    out = np.zeros((len(det), len(lines[0])), dtype=np.uint8)
    for i, line in enumerate(lines):
        out[i] = np.array([int(c) for c in line], dtype=np.uint8)
    return out


def decode_bposd(
    h: np.ndarray,
    a: np.ndarray,
    priors: np.ndarray,
    det: np.ndarray,
    *,
    max_iter: int,
    osd_order: int,
) -> np.ndarray:
    shots, _ = det.shape
    eta0 = shots * _PRIOR_OSD_SEC_PER_SHOT
    print(
        f"  constructing BpOsdDecoder … "
        f"(prior ETA for {shots} shots ≈ {fmt_duration(eta0)} "
        f"@ ~{_PRIOR_OSD_SEC_PER_SHOT:.0f}s/shot; live ETA updates below)",
        flush=True,
    )
    t_build = time.time()
    with Heartbeat("BpOsdDecoder construct"):
        decoder = BpOsdDecoder(
            h,
            error_channel=priors.tolist(),
            max_iter=max_iter,
            bp_method="minimum_sum",
            osd_method="osd_cs",
            osd_order=osd_order,
        )
    print(
        f"  BpOsdDecoder ready in {fmt_duration(time.time() - t_build)}",
        flush=True,
    )
    k = a.shape[0]
    out = np.zeros((shots, k), dtype=np.uint8)
    t0 = time.time()
    last_beat = t0
    for i in range(shots):
        e_hat = decoder.decode(det[i].astype(np.uint8))
        out[i] = (a @ e_hat) % 2
        now = time.time()
        done = i + 1
        # Progress every 10 shots OR every heartbeat interval (whichever first).
        if done % 10 == 0 or done == shots or (now - last_beat) >= _HEARTBEAT_SEC:
            elapsed = now - t0
            rate = done / elapsed if elapsed > 0 else 0.0
            remain = (shots - done) / rate if rate > 0 else float("nan")
            print(
                f"  bposd shot {done}/{shots} "
                f"elapsed={fmt_duration(elapsed)} "
                f"rate={rate:.3f} shot/s "
                f"ETA_remaining≈{fmt_duration(remain)}",
                flush=True,
            )
            last_beat = now
    return out


def run_one(
    *,
    circuit_name: str,
    p: float,
    shots: int,
    seed: int,
    bposd_max_iter: int,
    osd_order: int,
    skip_bposd: bool,
    binary: Path,
) -> list[dict]:
    """Matched-shot Relay vs BP+OSD (optional) for one (circuit, p). Müller gross defaults."""
    circuit_path = resolve_circuit(circuit_name, p)
    circuit = stim.Circuit.from_file(circuit_path)
    dem = circuit.detector_error_model(decompose_errors=False)
    print(f"p={p} building DEM matrices …", flush=True)
    t_dem = time.time()
    with Heartbeat("DEM matrix build"):
        h, a_mat, priors = dem_matrices(dem)
    print(
        f"circuit={circuit_path.name}\n"
        f"detectors={dem.num_detectors} observables={dem.num_observables} "
        f"errors={h.shape[1]} H={h.shape} "
        f"(DEM build {fmt_duration(time.time() - t_dem)})",
        flush=True,
    )
    if not skip_bposd:
        print(
            f"ETA plan: Relay batch (unknown; heartbeat {_HEARTBEAT_SEC:.0f}s) + "
            f"OSD ~{fmt_duration(shots * _PRIOR_OSD_SEC_PER_SHOT)} "
            f"(prior {_PRIOR_OSD_SEC_PER_SHOT:.0f}s/shot × {shots})",
            flush=True,
        )

    sampler = circuit.compile_detector_sampler(seed=seed)
    det, obs_true = sampler.sample(shots=shots, separate_observables=True)
    det = det.astype(np.uint8)
    obs_true = obs_true.astype(np.uint8)

    payload = dem_to_relay_payload(
        dem,
        relay={
            "stop_nconv": 1,
            "num_sets": 60,
            "pre_iter": 80,
            "set_max_iter": 60,
            "gamma0": 0.125,
            "gamma_lo": -0.24,
            "gamma_hi": 0.66,
            "seed": 1,
        },
    )
    print(f"p={p} decoding aether_relay ({shots} shots) …", flush=True)
    obs_relay = decode_relay(binary, payload, det)
    err_relay = int(np.any(obs_relay != obs_true, axis=1).sum())
    print(f"p={p} aether_relay done errors={err_relay}/{shots}", flush=True)

    pairs: list[tuple[str, int]] = [("aether_relay", err_relay)]
    if skip_bposd:
        print(
            "skip bposd_cs10 (Progress: OSD-CS10 too slow on gross at high p)",
            flush=True,
        )
    else:
        print(f"p={p} decoding bposd_cs10 ({shots} shots) …", flush=True)
        obs_bposd = decode_bposd(
            h,
            a_mat,
            priors,
            det,
            max_iter=bposd_max_iter,
            osd_order=osd_order,
        )
        pairs.append(("bposd_cs10", int(np.any(obs_bposd != obs_true, axis=1).sum())))
        print(
            f"p={p} bposd_cs10 done errors={pairs[-1][1]}/{shots}",
            flush=True,
        )

    rows = []
    for name, errors in pairs:
        ler = errors / shots
        lo, hi = wilson_interval(errors, shots)
        rows.append(
            {
                "circuit": circuit_name,
                "p": p,
                "shots": shots,
                "seed": seed,
                "decoder": name,
                "errors": errors,
                "ler": ler,
                "ler_lo": lo,
                "ler_hi": hi,
                "detectors": dem.num_detectors,
                "observables": dem.num_observables,
                "dem_errors": int(h.shape[1]),
            }
        )
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--circuit",
        default="bicycle_bivariate_18_4_3_memory_Z",
        help="IBM testdata circuit stem prefix (before ,distance=...)",
    )
    parser.add_argument(
        "--p",
        type=float,
        default=None,
        help="Single physical error rate (mutually exclusive with --ps)",
    )
    parser.add_argument(
        "--ps",
        type=str,
        default=None,
        help="Comma-separated p grid, e.g. 0.003,0.004,0.006 (mutually exclusive with --p)",
    )
    parser.add_argument("--shots", type=int, default=200)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--bposd-max-iter", type=int, default=10_000)
    parser.add_argument("--osd-order", type=int, default=10)
    parser.add_argument(
        "--skip-bposd",
        action="store_true",
        help="Relay-only (use for high-p gross where OSD-CS10 is impractical)",
    )
    parser.add_argument(
        "--skip-bposd-above",
        type=float,
        default=None,
        help="Skip BP+OSD for p greater than this (matched Relay still run)",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=ROOT / "results" / "relay_bb_bakeoff_m14.csv",
    )
    parser.add_argument(
        "--append",
        action="store_true",
        help="Append rows to --out if it exists (do not overwrite cited CSVs)",
    )
    args = parser.parse_args()

    if args.p is not None and args.ps is not None:
        raise SystemExit("pass only one of --p or --ps")
    if args.ps is not None:
        ps = [float(x) for x in args.ps.split(",") if x.strip()]
    elif args.p is not None:
        ps = [args.p]
    else:
        ps = [0.003]

    binary = ensure_relay_binary()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    total = 0
    for p in ps:
        skip = args.skip_bposd or (
            args.skip_bposd_above is not None and p > args.skip_bposd_above
        )
        rows = run_one(
            circuit_name=args.circuit,
            p=p,
            shots=args.shots,
            seed=args.seed,
            bposd_max_iter=args.bposd_max_iter,
            osd_order=args.osd_order,
            skip_bposd=skip,
            binary=binary,
        )
        fieldnames = list(rows[0].keys())
        write_header = not (
            (args.append or total > 0)
            and args.out.is_file()
            and args.out.stat().st_size > 0
        )
        mode = "a" if not write_header else "w"
        with args.out.open(mode, newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            if write_header:
                writer.writeheader()
            writer.writerows(rows)
        total += len(rows)
        for r in rows:
            print(
                f"p={r['p']} {r['decoder']:14} errors={r['errors']}/{r['shots']} "
                f"LER={r['ler']:.4g} Wilson=[{r['ler_lo']:.4g}, {r['ler_hi']:.4g}]",
                flush=True,
            )
        print(f"checkpoint wrote {args.out} (+{len(rows)} rows, total {total})", flush=True)

    print(f"done {args.out} ({total} rows)", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
