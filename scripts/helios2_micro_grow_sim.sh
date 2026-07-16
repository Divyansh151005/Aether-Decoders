#!/usr/bin/env bash
# M40: Helios-2 micro grow (H9 wired) + regressions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=150
echo "=== helios2_micro_grow_sim (M40) ==="
echo "ETA ≈ ${ETA_SEC}s (cargo + Icarus Helios-2/H9/mesh + Verilator; usually ≪ ETA)"
echo "Heartbeat every 10s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 10
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] helios2_micro_grow_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
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
echo "[$(date +%H:%M:%S)] Icarus Helios-2 micro grow …"
iverilog -g2012 -o tb_helios2_micro_sim \
  aether_uf_helios2_micro_grow.sv tb_aether_uf_helios2_micro_grow.sv
./tb_helios2_micro_sim
echo "[$(date +%H:%M:%S)] Helios-2 PASS"

echo "[$(date +%H:%M:%S)] Icarus H9 LUTRAM regression …"
iverilog -g2012 -o tb_pe_lutram_ctx_sim \
  aether_uf_pe_lutram_ctx.sv tb_aether_uf_pe_lutram_ctx.sv
./tb_pe_lutram_ctx_sim

echo "[$(date +%H:%M:%S)] Icarus PE-mesh decode smoke …"
cargo run --quiet --bin gen_rtl_vectors
iverilog -g2012 -o tb_pe_mesh_decode_sim \
  aether_uf_pe_graph_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv tb_aether_uf_pe_mesh_decode.sv
./tb_pe_mesh_decode_sim

if command -v verilator >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] Verilator Helios-2 …"
  rm -rf obj_dir_helios2_micro
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_helios2_micro_grow \
    -Mdir obj_dir_helios2_micro \
    -o tb_helios2_micro_verilator \
    aether_uf_helios2_micro_grow.sv tb_aether_uf_helios2_micro_grow.sv
  ./obj_dir_helios2_micro/tb_helios2_micro_verilator
  echo "[$(date +%H:%M:%S)] Verilator PASS"
else
  echo "[$(date +%H:%M:%S)] Verilator not found — skipped"
fi

EL=$(( $(date +%s) - T0 ))
echo "=== DONE helios2_micro_grow_sim in ${EL}s ==="
