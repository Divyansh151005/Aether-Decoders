#!/usr/bin/env bash
# M65: S4 circuit grow Yosys cliff (N=392 M=556). Spec: Docs/S4_Synth_M65.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RTL="$ROOT/rtl"
OUT="$ROOT/fpga/s4/out_m65"
CSV="$ROOT/results/fpga_s4_grow_m65.csv"
PART="xcvu13p-fhgb2104-2-e"
BOARD="VCU129"
FAMILY="xcup"
TOP="aether_uf_pe_mesh_s4_grow"
TIMEOUT=1800

mkdir -p "$OUT"
START=$(date +%s)
ETA=1200
echo "ETA: ~${ETA}s–${TIMEOUT}s S4 grow N392 (prior N16 grow ~330s; expect cliff)"
echo "part=$PART board=$BOARD"

(while true; do sleep 15; EL=$(( $(date +%s) - START )); REM=$((ETA - EL)); [[ $REM -lt 0 ]] && REM=0
  echo "[heartbeat] s4_grow elapsed=${EL}s ETA_remaining≈${REM}s" >&2
done) &
HB=$!
cleanup() { kill "$HB" 2>/dev/null || true; }
trap cleanup EXIT

set +e
perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" yosys -Q -p "
  read_verilog -sv $RTL/aether_uf_pe_graph_grow.sv $RTL/aether_uf_pe_mesh_s4_grow.sv
  hierarchy -check -top $TOP
  synth_xilinx -top $TOP -family $FAMILY
  tee -o $OUT/${TOP}.stat.txt stat
" >"$OUT/${TOP}.yosys.log" 2>&1
YS=$?
set -e

if [[ "$YS" -ne 0 || ! -f "$OUT/${TOP}.stat.txt" ]]; then
  {
    echo "dut,label,board,part,tool,lut,ff,bram,uram,cells,status,log"
    echo "$TOP,circuit_d3r3_N392_M556,$BOARD,$PART,yosys_xcup,,,,,timeout_or_fail,$YS,$OUT/${TOP}.yosys.log"
  } | tee "$CSV"
  echo "CLIFF/FAIL yosys_exit=$YS elapsed=$(( $(date +%s) - START ))s csv=$CSV"
  exit 0
fi

lut=$(awk '/^=== /{s=0} /^[[:space:]]+[0-9]+[[:space:]]+LUT[1-6]$/{s+=$1} END{print s+0}' "$OUT/${TOP}.stat.txt")
ff=$(awk '/^=== /{s=0} /^[[:space:]]+[0-9]+[[:space:]]+(FDRE|FDSE|FDCE|FDPE|FD)$/{s+=$1} END{print s+0}' "$OUT/${TOP}.stat.txt")
bram=$(awk '/^=== /{s=0} /^[[:space:]]+[0-9]+[[:space:]]+(RAMB36|RAMB18)/{s+=$1} END{print s+0}' "$OUT/${TOP}.stat.txt")
uram=$(awk '/^[[:space:]]+[0-9]+[[:space:]]+URAM288/{s+=$1} END{print s+0}' "$OUT/${TOP}.stat.txt")
cells=$(awk '/^[[:space:]]+[0-9]+[[:space:]]+cells$/{c=$1} END{print c+0}' "$OUT/${TOP}.stat.txt")

{
  echo "dut,label,board,part,tool,lut,ff,bram,uram,cells,status,log"
  echo "$TOP,circuit_d3r3_N392_M556,$BOARD,$PART,yosys_xcup,$lut,$ff,$bram,$uram,$cells,ok,$OUT/${TOP}.yosys.log"
} | tee "$CSV"

echo "done elapsed=$(( $(date +%s) - START ))s csv=$CSV"
