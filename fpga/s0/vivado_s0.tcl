# Vivado S0 batch (M56 G2 stub; M75 adds XDC clock + out-of-context place/route).
# Run on Linux/Windows with Vivado installed (not available on macOS):
#   vivado -mode batch -source fpga/s0/vivado_s0.tcl
# Target: AMD VCU129 / xcvu13p-fhgb2104-2-e (Helios arXiv:2406.08491 board family).
# Clock: fpga/s0/s0_clocks.xdc (100 MHz, Helios §Implementation choice).
# Do not treat Yosys smoke as a substitute for this report.

set part xcvu13p-fhgb2104-2-e
set root [file normalize [file join [file dirname [info script]] ../..]]
set out  [file join $root fpga/s0/out_vivado]
set xdc  [file join $root fpga/s0/s0_clocks.xdc]
file mkdir $out

proc run_dut {top srcs label has_clk} {
  global part root out xdc
  create_project -in_memory -part $part
  foreach f $srcs {
    read_verilog -sv [file join $root $f]
  }
  if {$has_clk} {
    read_xdc -mode out_of_context $xdc
  }
  synth_design -top $top -part $part -mode out_of_context
  report_utilization -file [file join $out ${top}_synth_util.rpt]
  opt_design
  place_design
  route_design
  report_utilization -file [file join $out ${top}_util.rpt]
  report_timing_summary -file [file join $out ${top}_timing.rpt]
  if {$has_clk} {
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
  } else {
    set wns "n/a"
  }
  puts "S0 Vivado done: $top ($label) WNS=$wns -> $out"
  close_project
}

run_dut aether_uf_or_tree          {rtl/aether_uf_or_tree.sv}          {N=8}             0
run_dut aether_uf_syndrome_ring    {rtl/aether_uf_syndrome_ring.sv}    {WIDTH=16_DEPTH=2} 1
run_dut aether_uf_obs_egress       {rtl/aether_uf_obs_egress.sv}       {MAX_E=128}       1
run_dut aether_uf_helios_n_lattice {rtl/aether_uf_helios_n_lattice.sv} {N_PHYS=16_N_CTX=16_SLOTS=16} 1

puts "S0 Vivado batch complete. File LUT/FF/LUTRAM/WNS from *_util.rpt / *_timing.rpt into a new results/ CSV (do not overwrite cited CSVs)."
