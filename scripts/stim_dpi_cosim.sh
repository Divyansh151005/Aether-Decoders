#!/usr/bin/env bash
# M28: Stim-scale DPI co-sim (default circuit d=3 r=3).
# ETA: cargo ~1 min; Verilator build ~1–2 min; sim usually <1 min for 2 cases.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KIND="${1:-circuit}"
DIST="${2:-3}"
ROUNDS="${3:-3}"
P="${4:-0.02}"
SHOTS="${5:-24}"
RTL_CASES="${6:-2}"

echo "=== Stim DPI harness: kind=$KIND d=$DIST r=$ROUNDS p=$P shots=$SHOTS rtl_cases=$RTL_CASES ==="
ETA_SEC=300
echo "ETA ≈ ${ETA_SEC}s / ~5 min wall (cargo + Verilator; usually 2–5 min)."
echo "Heartbeat every 15s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 15
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] stim_dpi_cosim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
  done
}
heartbeat &
HB_PID=$!
cleanup() {
  kill "${HB_PID}" 2>/dev/null || true
  wait "${HB_PID}" 2>/dev/null || true
}
trap cleanup EXIT

cargo test -p aether_decoders --quiet
cargo build -p aether_uf_dpi --release

GEN="$ROOT/rtl/gen"
mkdir -p "$GEN"
python3 - <<PY
import json, sys
from pathlib import Path
import stim

ROOT = Path("$ROOT")
sys.path.insert(0, str(ROOT / "python"))
from aether_decoders.dem import dem_to_payload

kind, d, rounds, p, shots = "$KIND", int("$DIST"), int("$ROUNDS"), float("$P"), int("$SHOTS")
if kind == "phenom":
    circuit = stim.Circuit.generated(
        "surface_code:rotated_memory_z",
        distance=d, rounds=rounds,
        after_clifford_depolarization=0,
        before_round_data_depolarization=p,
        before_measure_flip_probability=p,
        after_reset_flip_probability=0,
    )
elif kind == "circuit":
    circuit = stim.Circuit.generated(
        "surface_code:rotated_memory_z",
        distance=d, rounds=rounds,
        after_clifford_depolarization=p,
        before_round_data_depolarization=p,
        before_measure_flip_probability=p,
        after_reset_flip_probability=p,
    )
else:
    raise SystemExit(f"bad kind {kind}")

dem = circuit.detector_error_model(decompose_errors=True)
payload = dem_to_payload(dem)
det, _ = circuit.compile_detector_sampler(seed=1).sample(shots=shots, separate_observables=True)
gen = ROOT / "rtl" / "gen"
(gen / "dpi_stim_dem.json").write_text(json.dumps(payload))
with (gen / "dpi_stim_shots.txt").open("w") as f:
    for row in det:
        f.write("".join("1" if b else "0" for b in row) + "\n")
print(f"wrote DEM+shots under {gen} (detectors={payload['num_detectors']})")
PY

# Pre-gate software cosim via shared loader (also warms confidence before RTL)
cargo run --quiet --bin gen_stim_rtl_vectors -- \
  "$GEN/dpi_stim_dem.json" "$GEN/dpi_stim_shots.txt" "$GEN/stim_cases_dpi_gate.sv" "$RTL_CASES"

LIBDIR="$ROOT/target/release"
if [[ "$(uname -s)" == "Darwin" ]]; then
  export DYLD_LIBRARY_PATH="$LIBDIR${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
  LDFLAGS=(-LDFLAGS "-L$LIBDIR -laether_uf_dpi")
else
  export LD_LIBRARY_PATH="$LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  LDFLAGS=(-LDFLAGS "-L$LIBDIR -laether_uf_dpi -Wl,-rpath,$LIBDIR")
fi

cd "$ROOT/rtl"
rm -rf obj_dir_stim_dpi
verilator --binary -j 0 -Wall -Wno-fatal --timing \
  --top-module tb_aether_uf_stim_dpi \
  -Mdir obj_dir_stim_dpi \
  -o tb_stim_dpi_verilator \
  "${LDFLAGS[@]}" \
  aether_uf_grow_merge.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv tb_aether_uf_stim_dpi.sv

./obj_dir_stim_dpi/tb_stim_dpi_verilator

EL=$(( $(date +%s) - T0 ))
echo "M28 Stim DPI co-sim OK (wall ${EL}s)"
