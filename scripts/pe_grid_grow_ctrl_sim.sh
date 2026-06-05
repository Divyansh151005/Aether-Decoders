#!/usr/bin/env bash
# M31: Blueprint grow+merge with H8 OR-tree controller vs helios_pe goldens.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=90
echo "=== pe_grid_grow_ctrl_sim (M31) ==="
echo "ETA ≈ ${ETA_SEC}s (gen vectors + Icarus + Verilator; usually ≪ ETA)"
echo "Heartbeat every 10s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 10
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] pe_grid_grow_ctrl_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
  done
}
heartbeat &
HB_PID=$!
cleanup() {
  kill "${HB_PID}" 2>/dev/null || true
  wait "${HB_PID}" 2>/dev/null || true
}
trap cleanup EXIT

echo "[$(date +%H:%M:%S)] cargo gen_rtl_vectors …"
cargo run --quiet --bin gen_rtl_vectors

cd "$ROOT/rtl"
echo "[$(date +%H:%M:%S)] Icarus ctrl TB …"
iverilog -g2012 -o tb_grow_ctrl_sim \
  aether_uf_or_tree.sv aether_uf_grow_merge_ctrl.sv tb_aether_uf_grow_merge_ctrl.sv
./tb_grow_ctrl_sim
echo "[$(date +%H:%M:%S)] Icarus PASS"

# Monolithic regression still green
echo "[$(date +%H:%M:%S)] Icarus monolithic grow_merge regression …"
iverilog -g2012 -o tb_param_sim aether_uf_grow_merge.sv tb_aether_uf_grow_merge.sv
./tb_param_sim
echo "[$(date +%H:%M:%S)] monolithic PASS"

if command -v verilator >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] Verilator ctrl TB …"
  rm -rf obj_dir_grow_ctrl
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_grow_merge_ctrl \
    -Mdir obj_dir_grow_ctrl \
    -o tb_grow_ctrl_verilator \
    aether_uf_or_tree.sv aether_uf_grow_merge_ctrl.sv tb_aether_uf_grow_merge_ctrl.sv
  ./obj_dir_grow_ctrl/tb_grow_ctrl_verilator
  echo "[$(date +%H:%M:%S)] Verilator PASS"
else
  echo "[$(date +%H:%M:%S)] Verilator not found — skipped"
fi

EL=$(( $(date +%s) - T0 ))
echo "=== DONE pe_grid_grow_ctrl_sim in ${EL}s ==="
