#!/usr/bin/env bash
# M39 / H9: Helios-n LUTRAM dual-context PE + regressions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=150
echo "=== pe_lutram_ctx_sim (M39 H9) ==="
echo "ETA ≈ ${ETA_SEC}s (cargo + Icarus H9/mesh-decode smoke + Verilator; usually ≪ ETA)"
echo "Heartbeat every 10s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 10
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] pe_lutram_ctx_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
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
echo "[$(date +%H:%M:%S)] Icarus H9 LUTRAM ctx …"
iverilog -g2012 -o tb_pe_lutram_ctx_sim \
  aether_uf_pe_lutram_ctx.sv tb_aether_uf_pe_lutram_ctx.sv
./tb_pe_lutram_ctx_sim
echo "[$(date +%H:%M:%S)] Icarus H9 PASS"

echo "[$(date +%H:%M:%S)] Icarus PE-mesh decode smoke (regen vectors) …"
cargo run --quiet --bin gen_rtl_vectors
iverilog -g2012 -o tb_pe_mesh_decode_sim \
  aether_uf_pe_graph_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv tb_aether_uf_pe_mesh_decode.sv
./tb_pe_mesh_decode_sim
echo "[$(date +%H:%M:%S)] mesh decode smoke PASS"

if command -v verilator >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] Verilator H9 …"
  rm -rf obj_dir_pe_lutram_ctx
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_pe_lutram_ctx \
    -Mdir obj_dir_pe_lutram_ctx \
    -o tb_pe_lutram_ctx_verilator \
    aether_uf_pe_lutram_ctx.sv tb_aether_uf_pe_lutram_ctx.sv
  ./obj_dir_pe_lutram_ctx/tb_pe_lutram_ctx_verilator
  echo "[$(date +%H:%M:%S)] Verilator PASS"
else
  echo "[$(date +%H:%M:%S)] Verilator not found — skipped"
fi

EL=$(( $(date +%s) - T0 ))
echo "=== DONE pe_lutram_ctx_sim in ${EL}s ==="
