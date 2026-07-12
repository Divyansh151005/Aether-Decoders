#!/usr/bin/env bash
# M37: edge-list PE mesh — square + docs_peel + line4/pair regressions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=150
echo "=== pe_graph_grow_sim (M37) ==="
echo "ETA ≈ ${ETA_SEC}s (cargo + Icarus square/docs_peel/line4/pair + Verilator; usually ≪ ETA)"
echo "Heartbeat every 10s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 10
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] pe_graph_grow_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
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
echo "[$(date +%H:%M:%S)] Icarus square …"
iverilog -g2012 -o tb_pe_square_sim \
  aether_uf_pe_graph_grow.sv tb_aether_uf_pe_square_grow.sv
./tb_pe_square_sim
echo "[$(date +%H:%M:%S)] Icarus square PASS"

echo "[$(date +%H:%M:%S)] Icarus docs_peel (branch) …"
iverilog -g2012 -o tb_pe_docs_peel_sim \
  aether_uf_pe_graph_grow.sv tb_aether_uf_pe_docs_peel_grow.sv
./tb_pe_docs_peel_sim
echo "[$(date +%H:%M:%S)] docs_peel PASS"

echo "[$(date +%H:%M:%S)] Icarus line4 regression …"
iverilog -g2012 -o tb_pe_line4_sim \
  aether_uf_pe_line_grow.sv tb_aether_uf_pe_line4_grow.sv
./tb_pe_line4_sim
echo "[$(date +%H:%M:%S)] line4 PASS"

echo "[$(date +%H:%M:%S)] Icarus pe_pair regression …"
iverilog -g2012 -o tb_pe_pair_sim \
  aether_uf_pe_vertex.sv aether_uf_pe_pair_grow.sv tb_aether_uf_pe_pair_grow.sv
./tb_pe_pair_sim
echo "[$(date +%H:%M:%S)] pe_pair PASS"

if command -v verilator >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] Verilator square …"
  rm -rf obj_dir_pe_square
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_pe_square_grow \
    -Mdir obj_dir_pe_square \
    -o tb_pe_square_verilator \
    aether_uf_pe_graph_grow.sv tb_aether_uf_pe_square_grow.sv
  ./obj_dir_pe_square/tb_pe_square_verilator
  echo "[$(date +%H:%M:%S)] Verilator square PASS"

  echo "[$(date +%H:%M:%S)] Verilator docs_peel …"
  rm -rf obj_dir_pe_docs_peel
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_pe_docs_peel_grow \
    -Mdir obj_dir_pe_docs_peel \
    -o tb_pe_docs_peel_verilator \
    aether_uf_pe_graph_grow.sv tb_aether_uf_pe_docs_peel_grow.sv
  ./obj_dir_pe_docs_peel/tb_pe_docs_peel_verilator
  echo "[$(date +%H:%M:%S)] Verilator docs_peel PASS"
else
  echo "[$(date +%H:%M:%S)] Verilator not found — skipped"
fi

EL=$(( $(date +%s) - T0 ))
echo "=== DONE pe_graph_grow_sim in ${EL}s ==="
