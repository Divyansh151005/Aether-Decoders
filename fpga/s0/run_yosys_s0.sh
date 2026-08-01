#!/usr/bin/env bash
# S0 Yosys synth smoke (M56). Not Vivado timing / not Helios-class proof.
# Spec: Docs/S0_Synth_M56, Docs/Fpga_Bringup_Prep §5 S0.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RTL="$ROOT/rtl"
OUT_DIR="$ROOT/fpga/s0/out"
CSV="$ROOT/results/fpga_s0_synth_m56.csv"
PART="xcvu13p-fhgb2104-2-e"
BOARD="VCU129"
FAMILY="xcup"
TOOL="$(yosys -V 2>&1 | head -1)"

mkdir -p "$OUT_DIR"
START=$(date +%s)
echo "ETA: ~30–90s for two tiny S0 DUTs (OR-tree N=8 + syndrome_ring W=16 D=2)"
echo "tool=$TOOL part=$PART family=$FAMILY board=$BOARD"

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
  local lut ff bram uram cells
  # Yosys `stat` prints "COUNT   CELLTYPE" — count is $1.
  # Prefer the final hierarchy-inclusive block (last matching lines win if we sum carefully).
  # Sum only the last === design hierarchy === inclusive section when present;
  # else sum the last module block. Simpler: sum all LUT*/FD* lines and divide is wrong
  # for hierarchical designs — use `stat` after flatten via a second tee.
  lut=$(awk '
    /^=== design hierarchy ===/ {h=1; next}
    h && /^[[:space:]]+[0-9]+[[:space:]]+LUT[1-6]$/ {s+=$1}
    h && /^[[:space:]]+[0-9]+[[:space:]]+(FDRE|FDSE|FDCE|FDPE|FD)$/ {f+=$1}
    END {print s+0}
  ' "$OUT_DIR/${top}.stat.txt")
  ff=$(awk '
    /^=== design hierarchy ===/ {h=1; next}
    h && /^[[:space:]]+[0-9]+[[:space:]]+(FDRE|FDSE|FDCE|FDPE|FD)$/ {s+=$1}
    END {print s+0}
  ' "$OUT_DIR/${top}.stat.txt")
  # Flat tops (no hierarchy section body with LUT): fall back to last module block
  if [[ "$lut" -eq 0 && "$ff" -eq 0 ]]; then
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
  fi
  bram=$(awk '
    /^[[:space:]]+[0-9]+[[:space:]]+(RAMB36|RAMB18)/ {s+=$1}
    END {print s+0}
  ' "$OUT_DIR/${top}.stat.txt")
  uram=$(awk '
    /^[[:space:]]+[0-9]+[[:space:]]+URAM288/ {s+=$1}
    END {print s+0}
  ' "$OUT_DIR/${top}.stat.txt")
  cells=$(awk '/Number of cells:/{c=$4} END{print c+0}' "$OUT_DIR/${top}.stat.txt")
  if [[ "$cells" -eq 0 ]]; then
    cells=$(awk '
      /^[[:space:]]+[0-9]+[[:space:]]+cells$/ {c=$1}
      END {print c+0}
    ' "$OUT_DIR/${top}.stat.txt")
  fi
  echo "$top,$label,$BOARD,$PART,yosys_xcup,$lut,$ff,$bram,$uram,$cells,$log"
}

{
  echo "dut,label,board,part,tool,lut,ff,bram,uram,cells,log"
  synth_one aether_uf_or_tree \
    "$RTL/aether_uf_or_tree.sv" \
    "N=8"
  # Heartbeat between DUTs
  ELAP=$(( $(date +%s) - START ))
  echo "[heartbeat] elapsed=${ELAP}s ETA_remaining~45s" >&2
  synth_one aether_uf_syndrome_ring \
    "$RTL/aether_uf_syndrome_ring.sv" \
    "WIDTH=16_DEPTH=2"
} | tee "$CSV"

ELAP=$(( $(date +%s) - START ))
echo "done elapsed=${ELAP}s csv=$CSV"
