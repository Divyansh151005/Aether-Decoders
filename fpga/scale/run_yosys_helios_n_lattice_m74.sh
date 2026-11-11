#!/usr/bin/env bash
# M74: Yosys physical-lattice-only synth for Helios-n (M67 step 4; cite M66 flat N>=24 ABC timeout).
# DUT: rtl/aether_uf_helios_n_lattice.sv (context banks + slot growth); central merge excluded.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RTL="$ROOT/rtl"
OUT="$ROOT/fpga/scale/out_m74"
CSV="$ROOT/results/fpga_helios_n_lattice_m74.csv"
PART="xcvu13p-fhgb2104-2-e"
BOARD="VCU129"
FAMILY="xcup"

mkdir -p "$OUT"
START=$(date +%s)
ETA=900
echo "ETA: ~${ETA}s (M70 map lattice N_PHYS=7 then N_PHYS=16 upper bound; prior flat N16 ~330s)"
echo "part=$PART board=$BOARD"

(while true; do sleep 15; EL=$(( $(date +%s) - START )); REM=$((ETA - EL)); [[ $REM -lt 0 ]] && REM=0
  echo "[heartbeat] helios_n_lattice elapsed=${EL}s ETA_remaining≈${REM}s" >&2
done) &
HB=$!
cleanup() { kill "$HB" 2>/dev/null || true; }
trap cleanup EXIT

synth_one() {
  local label="$1" nphys="$2" nctx="$3" slots="$4" timeout_s="$5"
  local tag="helios_n_lattice_${label}"
  local log="$OUT/${tag}.yosys.log"
  echo "[$(date +%H:%M:%S)] synth $tag N_PHYS=$nphys N_CTX=$nctx SLOTS=$slots timeout=${timeout_s}s ..." >&2
  set +e
  perl -e 'alarm shift; exec @ARGV' "$timeout_s" yosys -Q -p "
    read_verilog -sv $RTL/aether_uf_helios_n_lattice.sv
    chparam -set N_PHYS $nphys -set N_CTX $nctx -set SLOTS $slots -set IDX_W 8 aether_uf_helios_n_lattice
    hierarchy -check -top aether_uf_helios_n_lattice
    synth_xilinx -top aether_uf_helios_n_lattice -family $FAMILY
    tee -o $OUT/${tag}.stat.txt stat
  " >"$log" 2>&1
  local ys=$?
  set -e
  if [[ "$ys" -ne 0 || ! -f "$OUT/${tag}.stat.txt" ]]; then
    echo "aether_uf_helios_n_lattice,$label,$nphys,$nctx,$slots,$BOARD,$PART,yosys_xcup,,,,,timeout_or_fail_$ys,${log#$ROOT/}"
    return 0
  fi
  local st="$OUT/${tag}.stat.txt" lut ff lutram cells
  lut=$(awk '/^[[:space:]]+[0-9]+[[:space:]]+LUT[1-6]$/{s+=$1} END{print s+0}' "$st")
  ff=$(awk '/^[[:space:]]+[0-9]+[[:space:]]+(FDRE|FDSE|FDCE|FDPE|FD)$/{s+=$1} END{print s+0}' "$st")
  lutram=$(awk '/^[[:space:]]+[0-9]+[[:space:]]+RAM(32|64|128|256)[A-Z0-9]*$/{s+=$1} END{print s+0}' "$st")
  cells=$(awk '/^[[:space:]]+[0-9]+[[:space:]]+cells$/{c=$1} END{print c+0}' "$st")
  echo "aether_uf_helios_n_lattice,$label,$nphys,$nctx,$slots,$BOARD,$PART,yosys_xcup,$lut,$ff,$lutram,$cells,ok,${log#$ROOT/}"
}

{
  echo "dut,label,n_phys,n_ctx,slots,board,part,tool,lut,ff,lutram_cells,cells,status,log"
  synth_one m70_map 7 16 12 1200
  synth_one nphys16_ub 16 16 16 1800
} | tee "$CSV"

echo "done elapsed=$(( $(date +%s) - START ))s csv=$CSV"
