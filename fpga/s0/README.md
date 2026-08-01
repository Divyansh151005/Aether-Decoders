# FPGA S0 project root (M56)

**Board (G1):** AMD/Xilinx **VCU129** (Helios arXiv:2406.08491).  
**Part:** `xcvu13p-fhgb2104-2-e` (VU13P; VCU129 kit FPGA).  
**Purchase:** not locked — literature / synth target only.

| Tool | Script | Status |
| --- | --- | --- |
| Yosys `synth_xilinx -family xcup` | `run_yosys_s0.sh` | Smoke for G3 counts |
| Vivado | `vivado_s0.tcl` | Stub until Vivado installed |

Evidence: `results/fpga_s0_synth_m56.csv`. Spec: `Docs/S0_Synth_M56`.
