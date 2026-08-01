#!/usr/bin/env bash
# M59: Yosys peel + grow→peel S1 (after packed ports + bounded BFS).
# Spec: Docs/Peel_Packed_M59. Do not overwrite fpga_s1_synth_m57.csv.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RTL="$ROOT/rtl"
OUT_DIR="$ROOT/fpga/s1/out_m59"
CSV="$ROOT/results/fpga_s1_peel_m59.csv"
PART="xcvu13p-fhgb2104-2-e"
BOARD="VCU129"
FAMILY="xcup"

mkdir -p "$OUT_DIR"
START=$(date +%s)
echo "ETA: ~60–180s Yosys peel N4 + grow→peel decode_s1"
echo "part=$PART board=$BOARD"

synth_one() {
  local top="$1"
  local files="$2"
  local label="$3"
  local log="$OUT_DIR/${top}.yosys.log"
  echo "[$(date +%H:%M:%S)] synth $top ($label) ..." >&2
  # shellcheck disable=SC2086
  yosys -Q -p "
    read_verilog -sv $files
    hierarchy -check -top $top
    synth_xilinx -top $top -family $FAMILY
    tee -o $OUT_DIR/${top}.stat.txt stat
  " >"$log" 2>&1
  local lut ff bram uram cells
  lut=$(awk '/^=== /{s=0} /^[[:space:]]+[0-9]+[[:space:]]+LUT[1-6]$/{s+=$1} END{print s+0}' "$OUT_DIR/${top}.stat.txt")
  ff=$(awk '/^=== /{s=0} /^[[:space:]]+[0-9]+[[:space:]]+(FDRE|FDSE|FDCE|FDPE|FD)$/{s+=$1} END{print s+0}' "$OUT_DIR/${top}.stat.txt")
  bram=$(awk '/^[[:space:]]+[0-9]+[[:space:]]+(RAMB36|RAMB18)/{s+=$1} END{print s+0}' "$OUT_DIR/${top}.stat.txt")
  uram=$(awk '/^[[:space:]]+[0-9]+[[:space:]]+URAM288/{s+=$1} END{print s+0}' "$OUT_DIR/${top}.stat.txt")
  cells=$(awk '/^[[:space:]]+[0-9]+[[:space:]]+cells$/{c=$1} END{print c+0}' "$OUT_DIR/${top}.stat.txt")
  echo "$top,$label,$BOARD,$PART,yosys_xcup,$lut,$ff,$bram,$uram,$cells,$log"
}

{
  echo "dut,label,board,part,tool,lut,ff,bram,uram,cells,log"
  # Wrapper with fixed params (chparam alone left default MAX_N=8 on bare peel)
  cat >"$OUT_DIR/peel_n4_top.sv" <<'EOF'
`timescale 1ns / 1ps
module aether_uf_peel_n4 (
    input  wire        clk, rst_n, start,
    input  wire [7:0]  num_nodes, num_edges,
    input  wire [3:0]  solid_bits,
    input  wire [31:0] syn_mem, bnd_mem,
    input  wire [31:0] eu_mem, ev_mem,
    output wire        done,
    output wire [3:0]  corr_bits,
    output wire [31:0] peel_ops
);
    aether_uf_peel #(.MAX_N(4), .MAX_E(4), .MAX_DEG(8), .IDX_W(8)) u (
        .clk(clk), .rst_n(rst_n), .start(start),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .solid_bits(solid_bits), .syn_mem(syn_mem), .bnd_mem(bnd_mem),
        .eu_mem(eu_mem), .ev_mem(ev_mem),
        .done(done), .corr_bits(corr_bits), .peel_ops(peel_ops)
    );
endmodule
EOF
  synth_one aether_uf_peel_n4 \
    "$RTL/aether_uf_peel.sv $OUT_DIR/peel_n4_top.sv" \
    "peel_MAX_N4"
  ELAP=$(( $(date +%s) - START ))
  echo "[heartbeat] elapsed=${ELAP}s ETA_remaining~120s" >&2
  synth_one aether_uf_pe_mesh_decode_s1 \
    "$RTL/aether_uf_pe_graph_grow.sv $RTL/aether_uf_peel.sv $RTL/aether_uf_pe_mesh_decode_s1.sv" \
    "grow_peel_N4_M4"
} | tee "$CSV"

echo "done elapsed=$(( $(date +%s) - START ))s csv=$CSV"
