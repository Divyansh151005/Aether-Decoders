#!/usr/bin/env bash
# M30: Verilator/Icarus sim of H8 OR-tree controller (PE-grid prep).
# Prints ETA + heartbeats so a quiet window is never "maybe stuck".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/rtl"

ETA_SEC=45
echo "=== pe_grid_or_tree_sim ==="
echo "ETA ≈ ${ETA_SEC}s (Icarus + Verilator if present; usually ≪ ETA)"
echo "Heartbeat every 5s until done."

T0=$(date +%s)
HB_PID=""
heartbeat() {
  while true; do
    sleep 5
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] pe_grid_or_tree_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
  done
}
heartbeat &
HB_PID=$!
cleanup() {
  if [[ -n "${HB_PID}" ]]; then
    kill "${HB_PID}" 2>/dev/null || true
    wait "${HB_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "[$(date +%H:%M:%S)] Icarus compile+sim …"
iverilog -g2012 -o tb_or_tree_sim aether_uf_or_tree.sv tb_aether_uf_or_tree.sv
./tb_or_tree_sim
echo "[$(date +%H:%M:%S)] Icarus PASS"

if command -v verilator >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] Verilator compile+sim …"
  rm -rf obj_dir_or_tree
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_or_tree \
    -Mdir obj_dir_or_tree \
    -o tb_or_tree_verilator \
    aether_uf_or_tree.sv tb_aether_uf_or_tree.sv
  ./obj_dir_or_tree/tb_or_tree_verilator
  echo "[$(date +%H:%M:%S)] Verilator PASS"
else
  echo "[$(date +%H:%M:%S)] Verilator not found — skipped (Icarus already PASS)"
fi

EL=$(( $(date +%s) - T0 ))
echo "=== DONE pe_grid_or_tree_sim in ${EL}s ==="
