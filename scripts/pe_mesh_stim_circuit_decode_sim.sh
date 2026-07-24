#!/usr/bin/env bash
# M47: Stim circuit d=3 r=3 → PE-mesh grow→peel (V=392 E=556) + smokes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=1800
echo "=== pe_mesh_stim_circuit_decode_sim (M47) ==="
echo "ETA ≈ ${ETA_SEC}s (cargo + Stim circuit d=3 r=3 + Verilator PE-mesh decode; M46 grow ~66s)"
echo "Heartbeat every 15s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 15
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] pe_mesh_stim_circuit_decode_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
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
    dem_path = td / "dem.json"
    shots_path = td / "shots.txt"
    dem_path.write_text(json.dumps(payload))
    with shots_path.open("w") as f:
        for row in det:
            f.write("".join("1" if b else "0" for b in row) + "\n")
    out = ROOT / "rtl" / "gen" / "stim_cases.sv"
    subprocess.check_call([
        "cargo", "run", "--quiet", "--bin", "gen_stim_rtl_vectors", "--",
        str(dem_path), str(shots_path), str(out), "2",
    ], cwd=ROOT)
print("generated circuit d=3 r=3 stim_cases.sv")
PY
}

echo "[$(date +%H:%M:%S)] gen Stim circuit d=3 r=3 vectors (2 RTL cases) …"
gen_circuit

cd "$ROOT/rtl"
if ! grep -q "localparam int STIM_N = 392" gen/stim_cases.sv; then
  echo "WARN: expected STIM_N=392 for circuit d=3 r=3; got:" >&2
  grep "localparam int STIM_" gen/stim_cases.sv | head -5 >&2 || true
fi

echo "[$(date +%H:%M:%S)] Icarus Blueprint mesh decode smoke …"
cargo run --quiet --bin gen_rtl_vectors
iverilog -g2012 -o tb_pe_mesh_decode_sim \
  aether_uf_pe_graph_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv tb_aether_uf_pe_mesh_decode.sv
./tb_pe_mesh_decode_sim

if ! command -v verilator >/dev/null 2>&1; then
  echo "ERROR: Verilator required for circuit PE-mesh decode (M24/M47)" >&2
  exit 1
fi

echo "[$(date +%H:%M:%S)] regen circuit vectors for Verilator …"
cd "$ROOT"
gen_circuit
cd "$ROOT/rtl"

echo "[$(date +%H:%M:%S)] Verilator PE-mesh circuit decode (N=600 MAX_DEG=64) …"
rm -rf obj_dir_pe_mesh_stim_circuit_decode
verilator --binary -j 0 -Wall -Wno-fatal --timing \
  --top-module tb_aether_uf_pe_mesh_stim_scale_decode \
  -Mdir obj_dir_pe_mesh_stim_circuit_decode \
  -o tb_pe_mesh_stim_circuit_decode_verilator \
  aether_uf_pe_graph_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv \
  tb_aether_uf_pe_mesh_stim_scale_decode.sv
./obj_dir_pe_mesh_stim_circuit_decode/tb_pe_mesh_stim_circuit_decode_verilator
echo "[$(date +%H:%M:%S)] Verilator decode PASS"

echo "[$(date +%H:%M:%S)] Verilator M46 grow regression …"
rm -rf obj_dir_pe_mesh_stim_circuit
verilator --binary -j 0 -Wall -Wno-fatal --timing \
  --top-module tb_aether_uf_pe_mesh_stim_scale \
  -Mdir obj_dir_pe_mesh_stim_circuit \
  -o tb_pe_mesh_stim_circuit_verilator \
  aether_uf_pe_graph_grow.sv tb_aether_uf_pe_mesh_stim_scale.sv
./obj_dir_pe_mesh_stim_circuit/tb_pe_mesh_stim_circuit_verilator
echo "[$(date +%H:%M:%S)] Verilator grow PASS"

EL=$(( $(date +%s) - T0 ))
echo "=== DONE pe_mesh_stim_circuit_decode_sim in ${EL}s ==="
