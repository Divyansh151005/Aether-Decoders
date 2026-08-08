#!/usr/bin/env bash
# S2 Yosys synth smoke (M58) — H9 LUTRAM ctx + Helios-2 micro grow.
# Spec: Docs/S2_Synth_M58, Docs/Fpga_Bringup_Prep §5 S2.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RTL="$ROOT/rtl"
OUT_DIR="$ROOT/fpga/s2/out"
CSV="$ROOT/results/fpga_s2_synth_m58.csv"
PART="xcvu13p-fhgb2104-2-e"
BOARD="VCU129"
FAMILY="xcup"
TOOL="$(yosys -V 2>&1 | head -1)"

mkdir -p "$OUT_DIR"
START=$(date +%s)
echo "ETA: ~30–90s for S2 H9 lutram_ctx + helios2_micro_grow"
echo "tool=$TOOL part=$PART family=$FAMILY board=$BOARD"
echo "LUTRAM bar: final BRAM/URAM must be 0 (distributed/FF banks OK)"

synth_one() {
  local top="$1"
  local files="$2"
  local label="$3"
  local log="$OUT_DIR/${top}.yosys.log"
  local json="$OUT_DIR/${top}.stat.json"
  echo "[$(date +%H:%M:%S)] synth $top ($label) ..." >&2
  # shellcheck disable=SC2086
  yosys -Q -p "
    read_verilog -sv $files
    hierarchy -check -top $top
    synth_xilinx -top $top -family $FAMILY
    tee -o $OUT_DIR/${top}.stat.txt stat
    write_json $json
  " >"$log" 2>&1
  local lut ff bram uram cells mem_to_regs
  lut=$(awk '
    /^=== / {s=0}
    /^[[:space:]]+[0-9]+[[:space:]]+LUT[1-6]$/ {s+=$1}
    END {print s+0}
  ' "$OUT_DIR/${top}.stat.txt")
  ff=$(awk '
    /^=== / {s=0}
    /^[[:space:]]+[0-9]+[[:space:]]+(FDRE|FDSE|FDCE|FDPE|FD)$/ {s+=$1}
    END {print s+0}
  ' "$OUT_DIR/${top}.stat.txt")
  bram=$(awk '
    /^[[:space:]]+[0-9]+[[:space:]]+(RAMB36|RAMB18)/ {s+=$1}
    END {print s+0}
  ' "$OUT_DIR/${top}.stat.txt")
  uram=$(awk '
    /^[[:space:]]+[0-9]+[[:space:]]+URAM288/ {s+=$1}
    END {print s+0}
  ' "$OUT_DIR/${top}.stat.txt")
  cells=$(awk '
    /^[[:space:]]+[0-9]+[[:space:]]+cells$/ {c=$1}
    END {print c+0}
  ' "$OUT_DIR/${top}.stat.txt")
  mem_to_regs=$(grep -c 'Replacing memory' "$log" || true)
  if [[ "$bram" -ne 0 || "$uram" -ne 0 ]]; then
    echo "FAIL LUTRAM bar: $top has bram=$bram uram=$uram (want 0)" >&2
    exit 1
  fi
  echo "$top,$label,$BOARD,$PART,yosys_xcup,$lut,$ff,$bram,$uram,$cells,$mem_to_regs,$log"
}

{
  echo "dut,label,board,part,tool,lut,ff,bram,uram,cells,mem_to_regs,log"
  synth_one aether_uf_pe_lutram_ctx \
    "$RTL/aether_uf_pe_lutram_ctx.sv" \
    "H9_N_CTX2"
  ELAP=$(( $(date +%s) - START ))
  echo "[heartbeat] elapsed=${ELAP}s ETA_remaining~45s" >&2
  synth_one aether_uf_helios2_micro_grow \
    "$RTL/aether_uf_helios2_micro_grow.sv" \
    "Helios2_N2_M1"
} | tee "$CSV"

ELAP=$(( $(date +%s) - START ))
echo "done elapsed=${ELAP}s csv=$CSV"
