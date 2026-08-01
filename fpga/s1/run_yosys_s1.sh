#!/usr/bin/env bash
# S1 Yosys synth smoke (M57) — Blueprint PE-mesh grow (N=4 + N=8).
# Spec: Docs/S1_Synth_M57, Docs/Fpga_Bringup_Prep §5 S1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RTL="$ROOT/rtl"
OUT_DIR="$ROOT/fpga/s1/out"
CSV="$ROOT/results/fpga_s1_synth_m57.csv"
PART="xcvu13p-fhgb2104-2-e"
BOARD="VCU129"
FAMILY="xcup"
TOOL="$(yosys -V 2>&1 | head -1)"

mkdir -p "$OUT_DIR"
START=$(date +%s)
echo "ETA: ~60–180s for S1 PE-mesh grow (N=4 Blueprint + N=8 headroom)"
echo "tool=$TOOL part=$PART family=$FAMILY board=$BOARD"
echo "note: peel not in Yosys (unpacked array ports); Verilator grows→peel separately"

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
  lut=$(awk '
    /^=== design hierarchy ===/ {h=1; next}
    h && /^[[:space:]]+[0-9]+[[:space:]]+LUT[1-6]$/ {s+=$1}
    END {print s+0}
  ' "$OUT_DIR/${top}.stat.txt")
  ff=$(awk '
    /^=== design hierarchy ===/ {h=1; next}
    h && /^[[:space:]]+[0-9]+[[:space:]]+(FDRE|FDSE|FDCE|FDPE|FD)$/ {s+=$1}
    END {print s+0}
  ' "$OUT_DIR/${top}.stat.txt")
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
  cells=$(awk '
    /^[[:space:]]+[0-9]+[[:space:]]+cells$/ {c=$1}
    END {print c+0}
  ' "$OUT_DIR/${top}.stat.txt")
  echo "$top,$label,$BOARD,$PART,yosys_xcup,$lut,$ff,$bram,$uram,$cells,$log"
}

{
  echo "dut,label,board,part,tool,lut,ff,bram,uram,cells,log"
  synth_one aether_uf_pe_mesh_s1_top \
    "$RTL/aether_uf_pe_graph_grow.sv $RTL/aether_uf_pe_mesh_s1_top.sv" \
    "Blueprint_N4_M4"
  ELAP=$(( $(date +%s) - START ))
  echo "[heartbeat] elapsed=${ELAP}s ETA_remaining~90s" >&2
  synth_one aether_uf_pe_mesh_s1_n8 \
    "$RTL/aether_uf_pe_graph_grow.sv $RTL/aether_uf_pe_mesh_s1_n8.sv" \
    "headroom_N8_M8"
} | tee "$CSV"

ELAP=$(( $(date +%s) - START ))
echo "done elapsed=${ELAP}s csv=$CSV"
