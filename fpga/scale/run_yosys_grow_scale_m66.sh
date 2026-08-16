#!/usr/bin/env bash
# M66: intermediate-N grow Yosys scale (N32, N64). Spec: Docs/Grow_Scale_M66.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RTL="$ROOT/rtl"
OUT="$ROOT/fpga/scale/out_m66"
CSV="$ROOT/results/fpga_grow_scale_m66.csv"
PART="xcvu13p-fhgb2104-2-e"
BOARD="VCU129"
FAMILY="xcup"

mkdir -p "$OUT"
START=$(date +%s)
ETA=1500
echo "ETA: ~${ETA}s N32 then N64 grow (prior N16 ~330s)"
echo "part=$PART board=$BOARD"

(while true; do sleep 15; EL=$(( $(date +%s) - START )); REM=$((ETA - EL)); [[ $REM -lt 0 ]] && REM=0
  echo "[heartbeat] grow_scale elapsed=${EL}s ETA_remaining≈${REM}s" >&2
done) &
HB=$!
cleanup() { kill "$HB" 2>/dev/null || true; }
trap cleanup EXIT

synth_one() {
  local top="$1"
  local wrapper="$2"
  local label="$3"
  local timeout_s="$4"
  local log="$OUT/${top}.yosys.log"
  echo "[$(date +%H:%M:%S)] synth $top ($label) timeout=${timeout_s}s ..." >&2
  set +e
  perl -e 'alarm shift; exec @ARGV' "$timeout_s" yosys -Q -p "
    read_verilog -sv $RTL/aether_uf_pe_graph_grow.sv $RTL/$wrapper
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
  # Cite priors as comment rows? Keep CSV machine rows only for new DUTs; priors in research note.
  synth_one aether_uf_pe_mesh_grow_n32 aether_uf_pe_mesh_grow_n32.sv "scale_N32_M36" 900
  synth_one aether_uf_pe_mesh_grow_n64 aether_uf_pe_mesh_grow_n64.sv "scale_N64_M72" 1200
} | tee "$CSV"

echo "done elapsed=$(( $(date +%s) - START ))s csv=$CSV"
