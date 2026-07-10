#!/usr/bin/env bash
# M34: two-PE neighbor-port grow vs Blueprint two_node golden.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=90
echo "=== pe_pair_grow_sim (M34) ==="
echo "ETA ≈ ${ETA_SEC}s (cargo test + Icarus + Verilator; usually ≪ ETA)"
echo "Heartbeat every 10s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 10
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] pe_pair_grow_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
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

cd "$ROOT/rtl"
echo "[$(date +%H:%M:%S)] Icarus pe_pair …"
iverilog -g2012 -o tb_pe_pair_sim \
  aether_uf_pe_vertex.sv aether_uf_pe_pair_grow.sv tb_aether_uf_pe_pair_grow.sv
./tb_pe_pair_sim
echo "[$(date +%H:%M:%S)] Icarus pe_pair PASS"

echo "[$(date +%H:%M:%S)] Icarus two_node regression …"
iverilog -g2012 -o tb_two_node_sim aether_uf_two_node_grow_merge.sv tb_aether_uf_two_node.sv
./tb_two_node_sim
echo "[$(date +%H:%M:%S)] two_node PASS"

if command -v verilator >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] Verilator pe_pair …"
  rm -rf obj_dir_pe_pair
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_pe_pair_grow \
    -Mdir obj_dir_pe_pair \
    -o tb_pe_pair_verilator \
    aether_uf_pe_vertex.sv aether_uf_pe_pair_grow.sv tb_aether_uf_pe_pair_grow.sv
  ./obj_dir_pe_pair/tb_pe_pair_verilator
  echo "[$(date +%H:%M:%S)] Verilator PASS"
else
  echo "[$(date +%H:%M:%S)] Verilator not found — skipped"
fi

EL=$(( $(date +%s) - T0 ))
echo "=== DONE pe_pair_grow_sim in ${EL}s ==="
