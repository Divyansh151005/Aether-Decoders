#!/usr/bin/env bash
# M72: Helios-n Stage D grow→peel co-sim vs decode_cosim (phenom d=3 r=3 / M45).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=90
echo "=== helios_n_decode_cosim_m72 ==="
echo "ETA ≈ ${ETA_SEC}s (cargo test + Stim phenom d=3 r=3 + Stage D vs cosim)"
echo "Heartbeat every 15s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 15
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] helios_n_decode_cosim_m72 still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
  done
}
heartbeat &
HB_PID=$!
cleanup() {
  kill "${HB_PID}" 2>/dev/null || true
  wait "${HB_PID}" 2>/dev/null || true
}
trap cleanup EXIT

echo "[$(date +%H:%M:%S)] cargo test …"
cargo test -p aether_decoders --quiet

echo "[$(date +%H:%M:%S)] gen Stim phenom d=3 r=3 + Stage D cosim …"
PYTHONPATH=python python3 - <<'PY'
import json, subprocess, tempfile
from pathlib import Path
import stim, sys
ROOT = Path(".").resolve()
sys.path.insert(0, str(ROOT / "python"))
from aether_decoders.dem import dem_to_payload

circuit = stim.Circuit.generated(
    "surface_code:rotated_memory_z",
    distance=3, rounds=3,
    after_clifford_depolarization=0,
    before_round_data_depolarization=0.02,
    before_measure_flip_probability=0.02,
    after_reset_flip_probability=0,
)
dem = circuit.detector_error_model(decompose_errors=True)
payload = dem_to_payload(dem)
sampler = circuit.compile_detector_sampler(seed=1)
det, _ = sampler.sample(shots=24, separate_observables=True)
with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    dem_path = td / "dem.json"
    shots_path = td / "shots.txt"
    dem_path.write_text(json.dumps(payload))
    with shots_path.open("w") as f:
        for row in det:
            f.write("".join("1" if b else "0" for b in row) + "\n")
    out = ROOT / "results" / "helios_n_decode_cosim_m72.csv"
    coloring = ROOT / "results" / "helios_n_coloring_m70.csv"
    subprocess.check_call([
        "cargo", "run", "--quiet", "--bin", "helios_n_decode_cosim", "--",
        str(dem_path), str(shots_path), str(coloring), str(out), "16",
    ], cwd=ROOT)
print("wrote", out)
PY

echo "[$(date +%H:%M:%S)] done."
