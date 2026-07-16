#!/usr/bin/env bash
# M69: H9 N_CTX=6 context-switch smoke (Helios-n schedule plan).
# Spec: Docs/Helios_n_Schedule_M69.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=60
echo "=== helios_n_ctx6_sim (M69) ==="
echo "ETA ≈ ${ETA_SEC}s"
T0=$(date +%s)
(while true; do sleep 10; EL=$(( $(date +%s) - T0 )); REM=$((ETA_SEC - EL));
  [[ $REM -lt 0 ]] && REM=0
  echo "[heartbeat] ctx6 elapsed=${EL}s ETA_remaining≈${REM}s" >&2
done) &
HB=$!
cleanup() { kill "$HB" 2>/dev/null || true; }
trap cleanup EXIT

echo "[$(date +%H:%M:%S)] cargo test …"
cargo test -p aether_decoders --quiet

cd "$ROOT/rtl"
echo "[$(date +%H:%M:%S)] Icarus N_CTX=6 …"
iverilog -g2012 -o tb_pe_lutram_ctx_n6_sim \
  aether_uf_pe_lutram_ctx.sv tb_aether_uf_pe_lutram_ctx_n6.sv
./tb_pe_lutram_ctx_n6_sim

if command -v verilator >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] Verilator N_CTX=6 …"
  rm -rf obj_dir_pe_lutram_ctx_n6
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_pe_lutram_ctx_n6 \
    -Mdir obj_dir_pe_lutram_ctx_n6 \
    -o tb_pe_lutram_ctx_n6_verilator \
    aether_uf_pe_lutram_ctx.sv tb_aether_uf_pe_lutram_ctx_n6.sv
  ./obj_dir_pe_lutram_ctx_n6/tb_pe_lutram_ctx_n6_verilator
fi

# Dual-context regression still green
echo "[$(date +%H:%M:%S)] Icarus N_CTX=2 regression …"
iverilog -g2012 -o tb_pe_lutram_ctx_sim \
  aether_uf_pe_lutram_ctx.sv tb_aether_uf_pe_lutram_ctx.sv
./tb_pe_lutram_ctx_sim

echo "=== DONE helios_n_ctx6_sim in $(( $(date +%s) - T0 ))s ==="
