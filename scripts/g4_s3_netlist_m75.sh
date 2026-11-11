#!/usr/bin/env bash
# M75 G4: S3 host path (ring → grow → peel → obs) RTL sim + host-shell synth_xilinx netlist sim
# vs Stim phenom d=3 r=1 goldens. Spec: Docs/G4_S3_Netlist_M75.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/fpga/s3/out_m75"
TOP="aether_uf_s3_host_top"
SHELL_NETLIST="$OUT/aether_uf_s3_host_shell.netlist.v"
CELLS_SIM="$(yosys-config --datdir)/xilinx/cells_sim.v"
mkdir -p "$OUT"

ETA_SEC=90
echo "=== g4_s3_netlist_m75 ==="
echo "ETA ≈ ${ETA_SEC}s (cargo test + Stim gen + RTL sim + Yosys shell ~8s + netlist sim ~7s)"
echo "Heartbeat every 15s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 15
    EL=$(( $(date +%s) - T0 )); REM=$((ETA_SEC - EL)); [[ $REM -lt 0 ]] && REM=0
    echo "[heartbeat] g4_s3_netlist_m75 still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
  done
}
heartbeat &
HB_PID=$!
cleanup() { kill "${HB_PID}" 2>/dev/null || true; wait "${HB_PID}" 2>/dev/null || true; }
trap cleanup EXIT

echo "[$(date +%H:%M:%S)] cargo test …"
cargo test -p aether_decoders --quiet

echo "[$(date +%H:%M:%S)] gen Stim phenom d=3 r=1 vectors (with OBS) …"
PYTHONPATH=python python3 - <<'PY'
import json, re, shutil, subprocess, tempfile
from pathlib import Path
import stim, sys
ROOT = Path(".").resolve()
sys.path.insert(0, str(ROOT / "python"))
from aether_decoders.dem import dem_to_payload
circuit = stim.Circuit.generated(
    "surface_code:rotated_memory_z", distance=3, rounds=1,
    after_clifford_depolarization=0,
    before_round_data_depolarization=0.02,
    before_measure_flip_probability=0.02,
    after_reset_flip_probability=0,
)
dem = circuit.detector_error_model(decompose_errors=True)
payload = dem_to_payload(dem)
det, _ = circuit.compile_detector_sampler(seed=1).sample(shots=24, separate_observables=True)
with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    (td / "dem.json").write_text(json.dumps(payload))
    with (td / "shots.txt").open("w") as f:
        for row in det:
            f.write("".join("1" if b else "0" for b in row) + "\n")
    # Generator also writes stim_run.sv beside its output; keep it in the temp dir.
    subprocess.check_call([
        "cargo", "run", "--quiet", "--bin", "gen_stim_rtl_vectors", "--",
        str(td / "dem.json"), str(td / "shots.txt"), str(td / "stim_cases.sv"), "8",
    ], cwd=ROOT)
    cases = (td / "stim_cases.sv").read_text()
    shutil.copy(td / "stim_cases.sv", ROOT / "rtl" / "gen" / "s3_host_cases.sv")
n = int(re.search(r"STIM_NUM_CASES = (\d+);", cases).group(1))
with (ROOT / "rtl" / "gen" / "s3_host_run.sv").open("w") as f:
    f.write("// Auto-generated run body — do not edit.\n")
    for i in range(n):
        f.write(f"clear_case(); load_stim_shot_{i}(); load_exp_{i}(); "
                f"run_shot({i}, C{i}_CYCLES, C{i}_PEEL_OPS, C{i}_OBS);\n")
print(f"generated s3_host_cases.sv ({n} cases)")
PY

cd "$ROOT/rtl"
RTL_SRCS=(aether_uf_syndrome_ring.sv aether_uf_pe_graph_grow.sv aether_uf_peel.sv
          aether_uf_pe_mesh_decode_s3.sv aether_uf_obs_egress.sv aether_uf_s3_host_top.sv)

echo "[$(date +%H:%M:%S)] Icarus RTL S3 host path …"
iverilog -g2012 -o tb_s3_host_rtl "${RTL_SRCS[@]}" tb_aether_uf_s3_host.sv
vvp -n ./tb_s3_host_rtl | tee "$OUT/rtl_sim.log" | grep -E "PASS|FAIL"
grep -q "ALL .* S3 HOST-PATH CASES PASS" "$OUT/rtl_sim.log"

# Full-top netlist (grow+peel core ~155k LUT / 260k cells) is not simulable on this host
# (Verilator frontend >30 min, Icarus ivl SIGKILL — Docs/G4_S3_Netlist_M75). Netlist the host shell
# (ring + sequencer + obs egress) with the decode core blackboxed; core stays RTL (≡ M45/M64).
echo "[$(date +%H:%M:%S)] Yosys synth_xilinx host shell (decode core blackboxed) …"
perl -e 'alarm shift; exec @ARGV' 600 yosys -Q -p "
  read_verilog -sv $ROOT/rtl/aether_uf_syndrome_ring.sv $ROOT/rtl/aether_uf_obs_egress.sv $ROOT/rtl/aether_uf_s3_host_top.sv
  read_verilog -sv -lib $ROOT/rtl/aether_uf_pe_mesh_decode_s3.sv
  hierarchy -check -top $TOP
  synth_xilinx -top $TOP -family xcup -flatten
  tee -o $OUT/aether_uf_s3_host_shell.stat.txt stat
  write_verilog -noattr $SHELL_NETLIST
" >"$OUT/aether_uf_s3_host_shell.yosys.log" 2>&1

echo "[$(date +%H:%M:%S)] Icarus netlist(shell)+RTL(core) sim …"
iverilog -g2012 -o tb_s3_host_netlist "$CELLS_SIM" "$SHELL_NETLIST" \
  aether_uf_pe_graph_grow.sv aether_uf_peel.sv aether_uf_pe_mesh_decode_s3.sv tb_aether_uf_s3_host.sv
vvp -n ./tb_s3_host_netlist | tee "$OUT/netlist_shell_sim.log" | grep -E "PASS|FAIL"
grep -q "ALL .* S3 HOST-PATH CASES PASS" "$OUT/netlist_shell_sim.log"

EL=$(( $(date +%s) - T0 ))
echo "=== DONE g4_s3_netlist_m75 in ${EL}s ==="
