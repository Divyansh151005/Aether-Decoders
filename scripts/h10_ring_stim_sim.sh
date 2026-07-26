#!/usr/bin/env bash
# M50: H10 depth-2 syndrome ring → PE-mesh Stim grow→peel (phenom d=3 r=1).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=200
echo "=== h10_ring_stim_sim (M50) ==="
echo "ETA ≈ ${ETA_SEC}s (cargo + Stim gen + Icarus/Verilator H10 ring decode)"
echo "Heartbeat every 10s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 10
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] h10_ring_stim_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
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

gen_r1() {
  PYTHONPATH=python python3 - <<'PY'
import json, subprocess, tempfile
from pathlib import Path
import stim, sys
ROOT = Path(".").resolve()
sys.path.insert(0, str(ROOT / "python"))
from aether_decoders.dem import dem_to_payload
circuit = stim.Circuit.generated(
    "surface_code:rotated_memory_z", distance=3, rounds=1,
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
    (td / "dem.json").write_text(json.dumps(payload))
    with (td / "shots.txt").open("w") as f:
        for row in det:
            f.write("".join("1" if b else "0" for b in row) + "\n")
    subprocess.check_call([
        "cargo", "run", "--quiet", "--bin", "gen_stim_rtl_vectors", "--",
        str(td / "dem.json"), str(td / "shots.txt"),
        str(ROOT / "rtl" / "gen" / "stim_cases.sv"), "4",
    ], cwd=ROOT)
print("generated phenom d=3 r=1 stim_cases.sv")
PY
}

echo "[$(date +%H:%M:%S)] gen Stim phenom d=3 r=1 …"
gen_r1

cd "$ROOT/rtl"
if ! grep -q "localparam int STIM_N = 16" gen/stim_cases.sv; then
  echo "WARN: expected STIM_N=16; got:" >&2
  grep "localparam int STIM_N" gen/stim_cases.sv >&2 || true
fi

echo "[$(date +%H:%M:%S)] Icarus H10 ring Stim …"
iverilog -g2012 -o tb_h10_ring_stim_sim \
  aether_uf_syndrome_ring.sv aether_uf_pe_graph_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv \
  tb_aether_uf_h10_ring_stim.sv
./tb_h10_ring_stim_sim
echo "[$(date +%H:%M:%S)] Icarus H10 PASS"

echo "[$(date +%H:%M:%S)] Icarus Blueprint mesh decode smoke …"
cargo run --quiet --bin gen_rtl_vectors
iverilog -g2012 -o tb_pe_mesh_decode_sim \
  aether_uf_pe_graph_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv tb_aether_uf_pe_mesh_decode.sv
./tb_pe_mesh_decode_sim

if command -v verilator >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] regen Stim for Verilator …"
  cd "$ROOT"
  gen_r1
  cd "$ROOT/rtl"
  rm -rf obj_dir_h10_ring
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_h10_ring_stim \
    -Mdir obj_dir_h10_ring \
    -o tb_h10_ring_verilator \
    aether_uf_syndrome_ring.sv aether_uf_pe_graph_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv \
    tb_aether_uf_h10_ring_stim.sv
  ./obj_dir_h10_ring/tb_h10_ring_verilator
  echo "[$(date +%H:%M:%S)] Verilator PASS"
else
  echo "[$(date +%H:%M:%S)] Verilator not found — skipped"
fi

EL=$(( $(date +%s) - T0 ))
echo "=== DONE h10_ring_stim_sim in ${EL}s ==="
