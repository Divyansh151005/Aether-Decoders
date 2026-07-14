#!/usr/bin/env bash
# M38: PE-mesh grow→peel (all Blueprint) + regressions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ETA_SEC=180
echo "=== pe_mesh_decode_sim (M38) ==="
echo "ETA ≈ ${ETA_SEC}s (cargo + gen vectors + Icarus mesh/square/docs + Verilator + M32 ctrl decode regression)"
echo "Heartbeat every 10s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 10
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] pe_mesh_decode_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
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
echo "[$(date +%H:%M:%S)] gen_rtl_vectors …"
cargo run --quiet --bin gen_rtl_vectors

cd "$ROOT/rtl"
echo "[$(date +%H:%M:%S)] Icarus PE-mesh decode (8 Blueprint) …"
iverilog -g2012 -o tb_pe_mesh_decode_sim \
  aether_uf_pe_graph_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv tb_aether_uf_pe_mesh_decode.sv
./tb_pe_mesh_decode_sim
echo "[$(date +%H:%M:%S)] Icarus PE-mesh decode PASS"

echo "[$(date +%H:%M:%S)] Icarus square grow regression …"
iverilog -g2012 -o tb_pe_square_sim \
  aether_uf_pe_graph_grow.sv tb_aether_uf_pe_square_grow.sv
./tb_pe_square_sim

echo "[$(date +%H:%M:%S)] Icarus docs_peel grow regression …"
iverilog -g2012 -o tb_pe_docs_peel_sim \
  aether_uf_pe_graph_grow.sv tb_aether_uf_pe_docs_peel_grow.sv
./tb_pe_docs_peel_sim

echo "[$(date +%H:%M:%S)] Icarus M32 ctrl decode regression …"
iverilog -g2012 -o tb_decode_ctrl_sim \
  aether_uf_or_tree.sv aether_uf_grow_merge_ctrl.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv \
  tb_aether_uf_decode_ctrl.sv
./tb_decode_ctrl_sim
echo "[$(date +%H:%M:%S)] M32 ctrl decode PASS"

if command -v verilator >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] Verilator PE-mesh decode …"
  rm -rf obj_dir_pe_mesh_decode
  verilator --binary -j 0 -Wall -Wno-fatal --timing \
    --top-module tb_aether_uf_pe_mesh_decode \
    -Mdir obj_dir_pe_mesh_decode \
    -o tb_pe_mesh_decode_verilator \
    aether_uf_pe_graph_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv tb_aether_uf_pe_mesh_decode.sv
  ./obj_dir_pe_mesh_decode/tb_pe_mesh_decode_verilator
  echo "[$(date +%H:%M:%S)] Verilator PASS"
else
  echo "[$(date +%H:%M:%S)] Verilator not found — skipped"
fi

EL=$(( $(date +%s) - T0 ))
echo "=== DONE pe_mesh_decode_sim in ${EL}s ==="
