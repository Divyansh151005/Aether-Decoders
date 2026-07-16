#!/usr/bin/env bash
# M41: Helios-2 micro grow→peel + regressions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=150
echo "=== helios2_micro_decode_sim (M41) ==="
echo "ETA ≈ ${ETA_SEC}s (cargo + Icarus Helios-2 decode/grow/H9 + Verilator; usually ≪ ETA)"
echo "Heartbeat every 10s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 10
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] helios2_micro_decode_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
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
echo "[$(date +%H:%M:%S)] Icarus Helios-2 micro decode …"
iverilog -g2012 -o tb_helios2_decode_sim \
  aether_uf_helios2_micro_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv \
  tb_aether_uf_helios2_micro_decode.sv
./tb_helios2_decode_sim
echo "[$(date +%H:%M:%S)] Helios-2 decode PASS"

echo "[$(date +%H:%M:%S)] Icarus Helios-2 grow regression …"
iverilog -g2012 -o tb_helios2_micro_sim \
  aether_uf_helios2_micro_grow.sv tb_aether_uf_helios2_micro_grow.sv
./tb_helios2_micro_sim

echo "[$(date +%H:%M:%S)] Icarus H9 regression …"
iverilog -g2012 -o tb_pe_lutram_ctx_sim \
  aether_uf_pe_lutram_ctx.sv tb_aether_uf_pe_lutram_ctx.sv
./tb_pe_lutram_ctx_sim

if command -v verilator >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] Verilator Helios-2 decode …"
  rm -rf obj_dir_helios2_decode
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_helios2_micro_decode \
    -Mdir obj_dir_helios2_decode \
    -o tb_helios2_decode_verilator \
    aether_uf_helios2_micro_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv \
    tb_aether_uf_helios2_micro_decode.sv
  ./obj_dir_helios2_decode/tb_helios2_decode_verilator
  echo "[$(date +%H:%M:%S)] Verilator PASS"
else
  echo "[$(date +%H:%M:%S)] Verilator not found — skipped"
fi

EL=$(( $(date +%s) - T0 ))
echo "=== DONE helios2_micro_decode_sim in ${EL}s ==="
