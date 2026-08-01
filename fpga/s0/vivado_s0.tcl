# Vivado S0 synth stub (M56 G2). Run when Vivado is installed:
#   vivado -mode batch -source fpga/s0/vivado_s0.tcl
# Target: AMD VCU129 / xcvu13p-fhgb2104-2-e (Helios arXiv:2406.08491 board family).
# Do not treat Yosys smoke as a substitute for this report.

set part xcvu13p-fhgb2104-2-e
set root [file normalize [file join [file dirname [info script]] ../..]]
set out  [file join $root fpga/s0/out_vivado]
file mkdir $out

proc synth_dut {top srcs label} {
  global part root out
  create_project -force s0_$top $out/proj_$top -part $part
  foreach f $srcs {
    add_files [file join $root $f]
  }
  set_property top $top [current_fileset]
  update_compile_order -fileset sources_1
  synth_design -top $top -part $part
  report_utilization -file [file join $out ${top}_util.rpt]
  report_timing_summary -file [file join $out ${top}_timing.rpt]
  close_project
  puts "S0 Vivado done: $top ($label) -> $out"
}

synth_dut aether_uf_or_tree {rtl/aether_uf_or_tree.sv} {N=8}
synth_dut aether_uf_syndrome_ring {rtl/aether_uf_syndrome_ring.sv} {WIDTH=16 DEPTH=2}

puts "S0 Vivado batch complete. File LUT/FF/BRAM/URAM from *_util.rpt into results/ (new CSV; do not overwrite threshold CSVs)."
