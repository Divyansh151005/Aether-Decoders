#!/usr/bin/env bash
# M52: H10 depth-2 ring → PE-mesh Stim grow→peel (circuit d=3 r=3).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=1800
echo "=== h10_ring_circuit_sim (M52) ==="
echo "ETA ≈ ${ETA_SEC}s (cargo + Stim circuit d=3 r=3 + Verilator H10 ring; M47 decode ~76s)"
echo "Heartbeat every 15s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 15
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] h10_ring_circuit_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
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

gen_circuit() {
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
    after_clifford_depolarization=0.02,
    before_round_data_depolarization=0.02,
    before_measure_flip_probability=0.02,
    after_reset_flip_probability=0.02,
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
        str(ROOT / "rtl" / "gen" / "stim_cases.sv"), "2",
    ], cwd=ROOT)
print("generated circuit d=3 r=3 stim_cases.sv")
PY
}

echo "[$(date +%H:%M:%S)] gen Stim circuit d=3 r=3 (2 RTL cases) …"
gen_circuit

cd "$ROOT/rtl"
if ! grep -q "localparam int STIM_N = 392" gen/stim_cases.sv; then
  echo "WARN: expected STIM_N=392; got:" >&2
  grep "localparam int STIM_N" gen/stim_cases.sv >&2 || true
fi

echo "[$(date +%H:%M:%S)] Icarus Blueprint mesh decode smoke …"
cargo run --quiet --bin gen_rtl_vectors
iverilog -g2012 -o tb_pe_mesh_decode_sim \
  aether_uf_pe_graph_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv tb_aether_uf_pe_mesh_decode.sv
./tb_pe_mesh_decode_sim

if ! command -v verilator >/dev/null 2>&1; then
  echo "ERROR: Verilator required for circuit H10 ring" >&2
  exit 1
fi

echo "[$(date +%H:%M:%S)] regen circuit for Verilator …"
cd "$ROOT"
gen_circuit
cd "$ROOT/rtl"

echo "[$(date +%H:%M:%S)] Verilator H10 ring circuit decode …"
rm -rf obj_dir_h10_ring_circuit
verilator --binary -j 0 -Wall -Wno-fatal --timing \
  --top-module tb_aether_uf_h10_ring_stim_scale \
  -Mdir obj_dir_h10_ring_circuit \
  -o tb_h10_ring_circuit_verilator \
  aether_uf_syndrome_ring.sv aether_uf_pe_graph_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv \
  tb_aether_uf_h10_ring_stim_scale.sv
./obj_dir_h10_ring_circuit/tb_h10_ring_circuit_verilator
echo "[$(date +%H:%M:%S)] Verilator PASS"

EL=$(( $(date +%s) - T0 ))
echo "=== DONE h10_ring_circuit_sim in ${EL}s ==="
