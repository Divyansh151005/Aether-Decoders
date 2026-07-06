#!/usr/bin/env bash
# M33: pipelined H8 OR-tree — depth vs clog2 + latency check.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/rtl"

ETA_SEC=60
echo "=== pe_grid_or_tree_pipe_sim (M33) ==="
echo "ETA ≈ ${ETA_SEC}s (Icarus + Verilator; usually ≪ ETA)"
echo "Heartbeat every 5s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 5
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] pe_grid_or_tree_pipe_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
  done
}
heartbeat &
HB_PID=$!
cleanup() {
  kill "${HB_PID}" 2>/dev/null || true
  wait "${HB_PID}" 2>/dev/null || true
}
trap cleanup EXIT

echo "[$(date +%H:%M:%S)] Icarus …"
iverilog -g2012 -o tb_or_tree_pipe_sim \
  aether_uf_or_tree_pipe.sv tb_aether_uf_or_tree_pipe.sv
./tb_or_tree_pipe_sim
echo "[$(date +%H:%M:%S)] Icarus PASS"

# Comb tree regression still green
echo "[$(date +%H:%M:%S)] Icarus comb OR-tree regression …"
iverilog -g2012 -o tb_or_tree_sim aether_uf_or_tree.sv tb_aether_uf_or_tree.sv
./tb_or_tree_sim
echo "[$(date +%H:%M:%S)] comb OR-tree PASS"

if command -v verilator >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] Verilator pipe TB …"
  rm -rf obj_dir_or_tree_pipe
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_or_tree_pipe \
    -Mdir obj_dir_or_tree_pipe \
    -o tb_or_tree_pipe_verilator \
    aether_uf_or_tree_pipe.sv tb_aether_uf_or_tree_pipe.sv
  ./obj_dir_or_tree_pipe/tb_or_tree_pipe_verilator
  echo "[$(date +%H:%M:%S)] Verilator PASS"
else
  echo "[$(date +%H:%M:%S)] Verilator not found — skipped"
fi

EL=$(( $(date +%s) - T0 ))
echo "=== DONE pe_grid_or_tree_pipe_sim in ${EL}s ==="
