# FPGA S1 project root (M57)

**Board/part:** VCU129 / `xcvu13p-fhgb2104-2-e` (M56 G1).  
**DUT:** Blueprint PE-mesh grow (`aether_uf_pe_mesh_s1_top` N=4; `aether_uf_pe_mesh_s1_n8`).  
**Peel:** not Yosys-synthable yet (unpacked ports) — Verilator grow→peel remains SoT.

| Script | Role |
| --- | --- |
| `run_yosys_s1.sh` | Yosys xcup resource smoke |
| `../s0/vivado_s0.tcl` | Vivado still S0-only stub |

Evidence: `results/fpga_s1_synth_m57.csv`. Spec: `Docs/S1_Synth_M57`.
