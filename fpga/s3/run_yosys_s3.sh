#!/usr/bin/env bash
# S3 Yosys smoke (M61): H10 ring W=16 + PE-mesh grow N16/M18 + peel S3.
# Spec: Docs/S3_Synth_M61. Do not overwrite M56–M60 CSVs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RTL="$ROOT/rtl"
OUT="$ROOT/fpga/s3/out"
CSV="$ROOT/results/fpga_s3_synth_m61.csv"
PART="xcvu13p-fhgb2104-2-e"
BOARD="VCU129"
FAMILY="xcup"

mkdir -p "$OUT"
START=$(date +%s)
echo "ETA: ~3–15 min S3 (ring + grow N16; peel may be longer)"
echo "part=$PART board=$BOARD"

synth_one() {
  local top="$1"
  local files="$2"
  local label="$3"
  local timeout_s="$4"
  local log="$OUT/${top}.yosys.log"
  echo "[$(date +%H:%M:%S)] synth $top ($label) timeout=${timeout_s}s ..." >&2
  set +e
  # shellcheck disable=SC2086
  perl -e 'alarm shift; exec @ARGV' "$timeout_s" yosys -Q -p "
    read_verilog -sv $files
    hierarchy -check -top $top
    synth_xilinx -top $top -family $FAMILY
    tee -o $OUT/${top}.stat.txt stat
  " >"$log" 2>&1
  local ys=$?
  set -e
  if [[ "$ys" -ne 0 || ! -f "$OUT/${top}.stat.txt" ]]; then
    echo "$top,$label,$BOARD,$PART,yosys_xcup,,,,,timeout_or_fail,$ys,$log"
    return 0
  fi
  local lut ff bram uram cells
  lut=$(awk '/^=== /{s=0} /^[[:space:]]+[0-9]+[[:space:]]+LUT[1-6]$/{s+=$1} END{print s+0}' "$OUT/${top}.stat.txt")
  ff=$(awk '/^=== /{s=0} /^[[:space:]]+[0-9]+[[:space:]]+(FDRE|FDSE|FDCE|FDPE|FD)$/{s+=$1} END{print s+0}' "$OUT/${top}.stat.txt")
  bram=$(awk '/^[[:space:]]+[0-9]+[[:space:]]+(RAMB36|RAMB18)/{s+=$1} END{print s+0}' "$OUT/${top}.stat.txt")
  uram=$(awk '/^[[:space:]]+[0-9]+[[:space:]]+URAM288/{s+=$1} END{print s+0}' "$OUT/${top}.stat.txt")
  cells=$(awk '/^[[:space:]]+[0-9]+[[:space:]]+cells$/{c=$1} END{print c+0}' "$OUT/${top}.stat.txt")
  echo "$top,$label,$BOARD,$PART,yosys_xcup,$lut,$ff,$bram,$uram,$cells,ok,$log"
}

{
  echo "dut,label,board,part,tool,lut,ff,bram,uram,cells,status,log"
  synth_one aether_uf_syndrome_ring \
    "$RTL/aether_uf_syndrome_ring.sv" \
    "WIDTH16_DEPTH2" 90
  ELAP=$(( $(date +%s) - START ))
  echo "[heartbeat] elapsed=${ELAP}s ETA_remaining~600s" >&2
  synth_one aether_uf_pe_mesh_s3_grow \
    "$RTL/aether_uf_pe_graph_grow.sv $RTL/aether_uf_pe_mesh_s3_grow.sv" \
    "phenom_d3r1_N16_M18" 600
  ELAP=$(( $(date +%s) - START ))
  echo "[heartbeat] elapsed=${ELAP}s peel next" >&2
  synth_one aether_uf_peel_s3 \
    "$RTL/aether_uf_peel.sv $RTL/aether_uf_peel_s3.sv" \
    "peel_N16_E18" 600
} | tee "$CSV"

echo "done elapsed=$(( $(date +%s) - START ))s csv=$CSV"
