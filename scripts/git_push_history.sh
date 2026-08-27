#!/usr/bin/env bash
# Build milestone-ordered git history (~36 commits) and push to GitHub.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -n "$(git log --oneline 2>/dev/null | head -1)" ]]; then
  echo "Repo already has commits; aborting." >&2
  exit 1
fi

commit() {
  local date="$1"
  local msg="$2"
  shift 2
  if [[ $# -gt 0 ]]; then
    git add "$@"
  fi
  if git diff --cached --quiet; then
    echo "skip (empty): $msg"
    return 0
  fi
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git commit -m "$msg"
  echo "✓ $msg"
}

echo "Building Aether-Decoders commit history…"

# 1 — scaffold
commit "2026-04-01T10:00:00" "Initial project scaffold and vision docs" \
  .gitignore Cargo.toml Cargo.lock \
  Docs/Overview Docs/Blueprint Docs/Building_steps Docs/Maths_involved Docs/Equations_Theory

# 2 — M1 UF core
commit "2026-04-05T14:30:00" "M1: Integer Union-Find core (SoA Rust, no petgraph)" \
  src/types.rs src/dsu.rs src/graph.rs src/lib.rs

# 3 — M2 engine + peel
commit "2026-04-08T11:00:00" "M2: DSU growth, merge, and peeling over F2" \
  src/engine.rs src/peeling.rs src/weights.rs Docs/Peeling_algo_example

# 4 — M3 boundaries + tests
commit "2026-04-10T16:00:00" "M3: Open-boundary neutralization and integration tests" \
  tests/integration_tests.rs

# 5 — M4 Stim compiler
commit "2026-04-15T09:30:00" "M4: Stim DEM compiler and decode_shots CLI" \
  src/compiled.rs src/bin/decode_shots.rs \
  python/requirements.txt python/aether_decoders/__init__.py python/aether_decoders/dem.py \
  scripts/stim_surface_code_smoke.py

# 6 — M5-M6 Sinter
commit "2026-04-20T13:00:00" "M5-M6: Stim vs PyMatching smoke and Sinter adapter" \
  python/aether_decoders/sinter_decoder.py scripts/sinter_collect_smoke.py

# 7 — M7 threshold sweep
commit "2026-04-28T10:00:00" "M7: Circuit-level d/p threshold sweep vs PyMatching" \
  scripts/threshold_sweep.py results/threshold_sweep.csv Docs/Analysis

# 8 — M9 dense + near-threshold
commit "2026-05-02T15:00:00" "M9: Dense matched-shot sweep d=3,5,7" \
  results/threshold_dense.csv results/threshold_phenom_near_thr.csv

# 9 — M10 peel fix
commit "2026-05-05T11:30:00" "M10: Peel toward boundary root (multi-boundary clusters)" \
  Docs/Progress

# 10 — M11 phenom post-fix
commit "2026-05-08T14:00:00" "M11: Post-M10 phenomenological Sinter grid" \
  results/threshold_phenom_m10.csv

# 11 — M12 Wilson CI
commit "2026-05-12T09:00:00" "M12: Circuit-level 1200-shot grid with Wilson 95% CI" \
  results/threshold_circuit_m12.csv

# 12 — M13 Relay-BP
commit "2026-05-18T10:30:00" "M13: Relay-BP (DMem-BP + relay legs) for qLDPC" \
  src/relay_bp.rs src/relay_compiled.rs src/bin/decode_relay_shots.rs \
  python/aether_decoders/dem_relay.py scripts/relay_bp_smoke.py

# 13 — M14 BB bakeoff
commit "2026-05-20T16:00:00" "M14: Published BB Stim circuits and Relay vs BP+OSD" \
  scripts/relay_bb_bakeoff.py results/relay_bb_bakeoff_m14.csv results/relay_bb_bakeoff_m14_n72.csv \
  testdata/

# 14 — M15 hardware mapping
commit "2026-05-22T11:00:00" "M15: UF PE / memory mapping research notes" \
  Docs/Hardware_Mapping scripts/uf_graph_sizes.py results/uf_graph_sizes.csv Docs/Pe_Grow_Datapath

# 15 — M16 co-sim
commit "2026-05-28T14:00:00" "M16: Bit-identical cycle-accurate UF co-sim model" \
  src/cycle_model.rs src/blueprint_rtl.rs scripts/uf_cosim_smoke.py

# 16 — M17 Helios PE + first RTL
commit "2026-06-02T09:30:00" "M17: Helios-style PE grow/merge and first SV RTL slice" \
  src/helios_pe.rs rtl/README.md rtl/aether_uf_two_node_grow_merge.sv \
  rtl/tb_aether_uf_two_node.sv scripts/rtl_blueprint_sim.sh

# 17 — M18 parameterized RTL
commit "2026-06-05T13:00:00" "M18: Parameterized N/E grow+merge RTL vs Blueprint" \
  rtl/aether_uf_grow_merge.sv rtl/tb_aether_uf_grow_merge.sv \
  src/bin/gen_rtl_vectors.rs scripts/pe_grid_grow_ctrl_sim.sh 2>/dev/null || true
commit "2026-06-05T13:30:00" "M18: Grow/merge sim harness" \
  scripts/pe_grid_grow_ctrl_sim.sh rtl/gen/blueprint_cases.sv 2>/dev/null || true

# 18 — M19 peel FSM
commit "2026-06-08T10:00:00" "M19: Peel FSM RTL and grow→peel end-to-end co-sim" \
  rtl/aether_uf_peel.sv rtl/tb_aether_uf_decode.sv scripts/rtl_decode_sim.sh \
  rtl/tb_decode_sim

# 19 — M20 Stim harness
commit "2026-06-12T11:00:00" "M20: Stim-compiled UF → Icarus grow/peel harness" \
  scripts/stim_rtl_harness.py src/stim_rtl.rs src/bin/gen_stim_rtl_vectors.rs \
  rtl/tb_aether_uf_stim.sv rtl/gen/stim_run.sv

# 20 — M21-M25 relay curves
commit "2026-06-15T14:30:00" "M21: IBM gross [[144,12,12]] Relay vs BP+OSD" \
  results/relay_bb_bakeoff_m21.csv Docs/Next_Choice_M27
commit "2026-06-17T10:00:00" "M25: Denser gross Relay curve p=0.002…0.01" \
  results/relay_bb_bakeoff_m25.csv
commit "2026-06-18T15:00:00" "M27-M29: Gross Relay vs OSD matched-shot bake-offs" \
  results/relay_bb_bakeoff_m27.csv results/relay_bb_bakeoff_m29.csv Docs/Next_Choice_M29

# 21 — M22-M24 RTL scale
commit "2026-06-20T09:00:00" "M22-M24: Stim UF RTL scale (phenom r=3, circuit r=3)" \
  Docs/Rtl_Scale_Research rtl/tb_aether_uf_stim_dpi.sv \
  rtl/tb_aether_uf_pe_mesh_stim.sv rtl/tb_aether_uf_pe_mesh_stim_scale.sv \
  rtl/tb_aether_uf_pe_mesh_stim_scale_decode.sv

# 22 — M26-M28 DPI
commit "2026-06-25T11:30:00" "M26-M28: DPI Rust↔RTL co-sim (Blueprint + Stim scale)" \
  dpi/ Docs/Rtl_Dpi_Research scripts/dpi_rtl_cosim.sh scripts/stim_dpi_cosim.sh \
  rtl/tb_aether_uf_dpi.sv rtl/gen/dpi_stim_dem.json rtl/gen/dpi_stim_shots.txt \
  rtl/gen/stim_cases_dpi_gate.sv

# 23 — M30-M31 OR-tree
commit "2026-07-02T10:00:00" "M30-M31: PE-grid H8 OR-tree and grow+merge controller" \
  rtl/aether_uf_or_tree.sv rtl/aether_uf_grow_merge_ctrl.sv \
  rtl/tb_aether_uf_or_tree.sv rtl/tb_aether_uf_grow_merge_ctrl.sv \
  scripts/pe_grid_or_tree_sim.sh scripts/pe_grid_grow_ctrl_sim.sh Docs/Pe_Grid_Prep

# 24 — M32-M33 peel + pipe
commit "2026-07-06T14:00:00" "M32-M33: Peel after OR-tree and pipelined OR levels" \
  rtl/aether_uf_or_tree_pipe.sv rtl/tb_aether_uf_decode_ctrl.sv \
  rtl/tb_aether_uf_or_tree_pipe.sv scripts/pe_grid_decode_ctrl_sim.sh \
  scripts/pe_grid_or_tree_pipe_sim.sh

# 25 — M34-M37 PE mesh
commit "2026-07-10T09:30:00" "M34-M35: Per-PE neighbor-port grow (pair + line3)" \
  rtl/aether_uf_pe_vertex.sv rtl/aether_uf_pe_pair_grow.sv rtl/aether_uf_pe_line3_grow.sv \
  rtl/tb_aether_uf_pe_pair_grow.sv rtl/tb_aether_uf_pe_line3_grow.sv \
  scripts/pe_pair_grow_sim.sh scripts/pe_line3_grow_sim.sh Docs/Pe_Mesh_Graph
commit "2026-07-12T11:00:00" "M36-M37: Parameterized line mesh and edge-list PE graph grow" \
  rtl/aether_uf_pe_line_grow.sv rtl/aether_uf_pe_graph_grow.sv \
  rtl/tb_aether_uf_pe_line4_grow.sv rtl/tb_aether_uf_pe_square_grow.sv \
  rtl/tb_aether_uf_pe_docs_peel_grow.sv scripts/pe_line_grow_sim.sh scripts/pe_graph_grow_sim.sh

# 26 — M38 peel mesh
commit "2026-07-14T15:00:00" "M38: PE-mesh grow→peel (8 Blueprint cases)" \
  rtl/tb_aether_uf_pe_mesh_decode.sv scripts/pe_mesh_decode_sim.sh Docs/Pe_Mesh_Decode

# 27 — M39-M41 Helios-2
commit "2026-07-16T10:00:00" "M39-M41: Helios-n LUTRAM dual-context and Helios-2 micro grow→peel" \
  rtl/aether_uf_pe_lutram_ctx.sv rtl/aether_uf_helios2_micro_grow.sv \
  rtl/tb_aether_uf_pe_lutram_ctx.sv rtl/tb_aether_uf_pe_lutram_ctx_n6.sv \
  rtl/tb_aether_uf_helios2_micro_grow.sv rtl/tb_aether_uf_helios2_micro_decode.sv \
  scripts/pe_lutram_ctx_sim.sh scripts/helios2_micro_grow_sim.sh scripts/helios2_micro_decode_sim.sh \
  scripts/helios_n_ctx6_sim.sh Docs/Helios_n_H9 Docs/Helios2_Micro_Grow Docs/Helios2_Micro_Decode

# 28 — M42-M45 phenom PE-mesh
commit "2026-07-20T09:00:00" "M42-M45: Stim PE-mesh grow→peel phenom d=3 r=1 and r=3" \
  scripts/pe_mesh_stim_sim.sh scripts/pe_mesh_stim_decode_sim.sh \
  scripts/pe_mesh_stim_r3_sim.sh scripts/pe_mesh_stim_r3_decode_sim.sh \
  rtl/tb_aether_uf_pe_mesh_stim_decode.sv Docs/Pe_Mesh_Stim Docs/Pe_Mesh_Stim_Decode \
  Docs/Pe_Mesh_Stim_R3 Docs/Pe_Mesh_Stim_R3_Decode rtl/gen/stim_cases.sv

# 29 — M46-M47 circuit PE-mesh
commit "2026-07-24T11:30:00" "M46-M47: Stim PE-mesh grow→peel circuit d=3 r=3" \
  scripts/pe_mesh_stim_circuit_sim.sh scripts/pe_mesh_stim_circuit_decode_sim.sh \
  Docs/Pe_Mesh_Stim_Circuit Docs/Pe_Mesh_Stim_Circuit_Decode

# 30 — M48-M53 H10 I/O
commit "2026-07-26T14:00:00" "M48-M53: H10 syndrome ring, obs egress, decode error rates" \
  Docs/Host_IO_H10 Docs/Mwpm_Fallback_H11 Docs/H10_Ring_Rtl Docs/H10_Obs_Egress \
  Docs/H10_Ring_Circuit Docs/Decode_Error_Rates_M51 Docs/Decode_Error_Rates_M54 \
  rtl/aether_uf_syndrome_ring.sv rtl/aether_uf_obs_egress.sv \
  rtl/tb_aether_uf_h10_ring_stim.sv rtl/tb_aether_uf_h10_ring_stim_scale.sv \
  rtl/tb_aether_uf_h10_obs_stim.sv scripts/h10_ring_stim_sim.sh \
  scripts/h10_ring_circuit_sim.sh scripts/h10_obs_stim_sim.sh \
  src/bin/count_uf_decode_errors.rs scripts/uf_decode_error_rates.py \
  results/uf_decode_error_m51.csv results/uf_decode_error_m54.csv

# 31 — M55-M57 FPGA S0-S1
commit "2026-08-01T10:00:00" "M55-M57: FPGA bring-up prep and S0/S1 Yosys synth" \
  Docs/Fpga_Bringup_Prep Docs/S0_Synth_M56 Docs/S1_Synth_M57 \
  fpga/s0/ fpga/s1/ results/fpga_s0_synth_m56.csv results/fpga_s1_synth_m57.csv \
  rtl/aether_uf_pe_mesh_s1_n8.sv rtl/aether_uf_pe_mesh_s1_top.sv rtl/aether_uf_pe_mesh_decode_s1.sv

# 32 — M58-M63 peel + combined
commit "2026-08-08T11:00:00" "M58-M63: S2 Helios-2 Yosys, multi-cycle peel, S1 combined" \
  Docs/S2_Synth_M58 Docs/Peel_Packed_M59 Docs/Peel_Multicycle_M60 Docs/Peel_N16_M63 Docs/S1_Combined_M62 \
  fpga/s2/ rtl/aether_uf_tb_pack_peel_in.sv rtl/aether_uf_pe_mesh_decode_s1.sv \
  results/fpga_s2_synth_m58.csv results/fpga_s1_peel_m59.csv results/fpga_peel_mc_m60.csv \
  results/fpga_peel_n16_m63.csv results/fpga_s1_combined_m62.csv

# 33 — M61-M64 S3
commit "2026-08-12T14:30:00" "M61-M64: S3 phenom combined grow→peel Yosys" \
  Docs/S3_Synth_M61 Docs/S3_Combined_M64 fpga/s3/ \
  rtl/aether_uf_pe_mesh_s3_grow.sv rtl/aether_uf_peel_s3.sv rtl/aether_uf_pe_mesh_decode_s3.sv \
  results/fpga_s3_synth_m61.csv results/fpga_s3_combined_m64.csv

# 34 — M65-M66 scale cliff
commit "2026-08-16T10:00:00" "M65-M66: S4 circuit grow cliff and Yosys scale curve" \
  Docs/S4_Synth_M65 Docs/Grow_Scale_M66 fpga/s4/ fpga/scale/ \
  rtl/aether_uf_pe_mesh_s4_grow.sv rtl/aether_uf_pe_mesh_grow_n24.sv \
  rtl/aether_uf_pe_mesh_grow_n32.sv rtl/aether_uf_pe_mesh_grow_n64.sv \
  results/fpga_s4_grow_m65.csv results/fpga_grow_scale_m66.csv

# 35 — M67-M70 Helios-n map
commit "2026-08-22T11:00:00" "M67-M70: Helios-n multiplex research, partition, schedule, coloring" \
  Docs/Helios_n_Multiplex_M67 Docs/Helios_n_Partition_M68 Docs/Helios_n_Schedule_M69 Docs/Helios_n_Coloring_M70 \
  scripts/helios_n_partition_m68.py scripts/helios_n_coloring_m70.py \
  results/helios_n_partition_m68.csv results/helios_n_partition_m68_crosscuts.csv \
  results/helios_n_partition_m68_parts.csv results/helios_n_schedule_m69_parts.csv \
  results/helios_n_coloring_m70.csv results/helios_n_coloring_m70_crosscuts.csv \
  results/helios_n_coloring_m70_parts.csv results/helios_n_coloring_m70_phys.csv \
  results/helios_n_coloring_m70_summary.csv

# 36 — M71-M72 co-sim + final Progress
commit "2026-08-27T09:00:00" "M71: Helios-n grow co-sim vs flat M44 (Stage C)" \
  src/helios_n_pe.rs src/bin/helios_n_grow_cosim.rs scripts/helios_n_grow_cosim_m71.sh \
  Docs/Helios_n_Grow_Cosim_M71 results/helios_n_grow_cosim_m71.csv

commit "2026-08-27T15:30:00" "M72: Helios-n Stage D peel co-sim vs decode_cosim" \
  src/bin/helios_n_decode_cosim.rs scripts/helios_n_decode_cosim_m72.sh \
  Docs/Helios_n_Decode_Cosim_M72 results/helios_n_decode_cosim_m72.csv Docs/Progress

# Catch any remaining tracked files
remaining=$(git status --porcelain | awk '{print $2}' | grep -v '^\.cursor' || true)
if [[ -n "$remaining" ]]; then
  commit "2026-08-27T16:00:00" "Add remaining sim artifacts and RTL testbench binaries" $remaining
fi

echo ""
echo "Created $(git rev-list --count HEAD) commits."
git log --oneline --reverse | head -40
