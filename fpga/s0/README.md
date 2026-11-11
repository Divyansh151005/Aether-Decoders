# FPGA S0 project root (M56; M75 Vivado prep)

**Board (G1):** AMD/Xilinx **VCU129** (Helios arXiv:2406.08491).  
**Part:** `xcvu13p-fhgb2104-2-e` (VU13P; VCU129 kit FPGA).  
**Purchase:** not locked — literature / synth target only.

| Tool | Script | Status |
| --- | --- | --- |
| Yosys `synth_xilinx -family xcup` | `run_yosys_s0.sh` | Smoke for G3 counts |
| Vivado | `vivado_s0.tcl` + `s0_clocks.xdc` | Ready (OOC synth → place → route, utilization + timing reports); **not run** — Vivado unavailable on macOS host |

Clock: 100 MHz (`create_clock -period 10.000`), cited from Helios §Implementation choice.
DUTs: OR-tree N=8, syndrome ring W=16 D=2, obs egress MAX_E=128 (M75 synthesizable), Helios-n lattice N_PHYS=16 (M74).

Evidence: `results/fpga_s0_synth_m56.csv` (Yosys). Spec: `Docs/S0_Synth_M56`, `Docs/G4_S3_Netlist_M75`.
