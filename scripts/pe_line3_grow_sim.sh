#!/usr/bin/env bash
# M35: 3-PE line mesh neighbor-port grow vs Blueprint line3.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=90
echo "=== pe_line3_grow_sim (M35) ==="
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
    echo "[heartbeat] pe_line3_grow_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
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
echo "[$(date +%H:%M:%S)] Icarus line3 …"
iverilog -g2012 -o tb_pe_line3_sim \
  aether_uf_pe_line3_grow.sv tb_aether_uf_pe_line3_grow.sv
./tb_pe_line3_sim
echo "[$(date +%H:%M:%S)] Icarus line3 PASS"

echo "[$(date +%H:%M:%S)] Icarus pe_pair regression …"
iverilog -g2012 -o tb_pe_pair_sim \
  aether_uf_pe_vertex.sv aether_uf_pe_pair_grow.sv tb_aether_uf_pe_pair_grow.sv
./tb_pe_pair_sim
echo "[$(date +%H:%M:%S)] pe_pair PASS"

if command -v verilator >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] Verilator line3 …"
  rm -rf obj_dir_pe_line3
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_pe_line3_grow \
    -Mdir obj_dir_pe_line3 \
    -o tb_pe_line3_verilator \
    aether_uf_pe_line3_grow.sv tb_aether_uf_pe_line3_grow.sv
  ./obj_dir_pe_line3/tb_pe_line3_verilator
  echo "[$(date +%H:%M:%S)] Verilator PASS"
else
  echo "[$(date +%H:%M:%S)] Verilator not found — skipped"
fi

EL=$(( $(date +%s) - T0 ))
echo "=== DONE pe_line3_grow_sim in ${EL}s ==="
