# S0 clock constraint (M75). Out-of-context: `clk` is a top-level port, no pin LOCs.
# 100 MHz = Helios arXiv:2406.08491 §"Implementation choice" ("For most experiments, we
# synthesize the design targeting a clock frequency of 100 MHz") on VCU129.
# Helios Table 1 fmax at d=3: 260 MHz phenom / 195 MHz circuit — not a target for Aether.
create_clock -period 10.000 -name clk [get_ports clk]
