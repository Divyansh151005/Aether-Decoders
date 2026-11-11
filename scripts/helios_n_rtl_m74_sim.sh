#!/usr/bin/env bash
# M74: Helios-n time-multiplexed grow RTL (M70 map) → peel vs M71/M72 oracle (phenom d=3 r=3).
# Verilator by default (~3 s sim); set HN_ICARUS=1 to also run Icarus (~40 min, ~1.4k clk/s).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "${HN_ICARUS:-0}" == "1" ]]; then ETA_SEC=2700; SIMS="Verilator+Icarus"; else ETA_SEC=120; SIMS="Verilator"; fi
echo "=== helios_n_rtl_m74_sim ==="
echo "ETA ≈ ${ETA_SEC}s (cargo test + Stim phenom d=3 r=3 + oracle-gated vectors + ${SIMS})"
echo "Heartbeat every 15s until done."

T0=$(date +%s)
heartbeat() {
  while true; do
    sleep 15
    NOW=$(date +%s)
    EL=$((NOW - T0))
    REM=$((ETA_SEC - EL))
    if [[ $REM -lt 0 ]]; then REM=0; fi
    echo "[heartbeat] helios_n_rtl_m74_sim still running… elapsed=${EL}s ETA_remaining≈${REM}s" >&2
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

echo "[$(date +%H:%M:%S)] gen Stim phenom d=3 r=3 + oracle-gated Helios-n vectors …"
PYTHONPATH=python python3 - <<'PY'
import json, subprocess, tempfile
from pathlib import Path
import stim, sys
ROOT = Path(".").resolve()
sys.path.insert(0, str(ROOT / "python"))
from aether_decoders.dem import dem_to_payload

circuit = stim.Circuit.generated(
    "surface_code:rotated_memory_z",
    distance=3, rounds=3,
    after_clifford_depolarization=0,
    before_round_data_depolarization=0.02,
    before_measure_flip_probability=0.02,
    after_reset_flip_probability=0,
)
dem = circuit.detector_error_model(decompose_errors=True)
payload = dem_to_payload(dem)
sampler = circuit.compile_detector_sampler(seed=1)
det, _ = sampler.sample(shots=24, separate_observables=True)
with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    dem_path = td / "dem.json"
    shots_path = td / "shots.txt"
    dem_path.write_text(json.dumps(payload))
    with shots_path.open("w") as f:
        for row in det:
            f.write("".join("1" if b else "0" for b in row) + "\n")
    subprocess.check_call([
        "cargo", "run", "--quiet", "--bin", "gen_helios_n_rtl_vectors", "--",
        str(dem_path), str(shots_path),
        str(ROOT / "results" / "helios_n_coloring_m70.csv"),
        str(ROOT / "rtl" / "gen" / "helios_n_cases.sv"), "16",
    ], cwd=ROOT)
PY

cd "$ROOT/rtl"
SRCS=(aether_uf_helios_n_lattice.sv aether_uf_helios_n_grow.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv tb_aether_uf_helios_n_decode.sv)

echo "[$(date +%H:%M:%S)] Verilator Helios-n grow→peel …"
rm -rf obj_dir_helios_n_m74
verilator --binary -j 0 -Wno-fatal -Wno-lint -Wno-style --timing \
  --top-module tb_aether_uf_helios_n_decode \
  -Mdir obj_dir_helios_n_m74 -o tb_helios_n_m74_verilator "${SRCS[@]}"
./obj_dir_helios_n_m74/tb_helios_n_m74_verilator

if [[ "${HN_ICARUS:-0}" == "1" ]]; then
  # Exact M70-map lattice (N_PHYS=7, SLOTS=12); 16x16 read fan-out is ~20x slower in Icarus.
  echo "[$(date +%H:%M:%S)] Icarus Helios-n grow→peel (M70 config) …"
  iverilog -g2012 -DHN_TB_NPHYS=7 -DHN_TB_SLOTS=12 -o tb_helios_n_m74_sim "${SRCS[@]}"
  vvp -n ./tb_helios_n_m74_sim
fi

EL=$(( $(date +%s) - T0 ))
echo "=== DONE helios_n_rtl_m74_sim in ${EL}s ==="
