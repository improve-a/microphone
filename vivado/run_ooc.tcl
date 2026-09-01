set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set report_dir [file join $repo_dir reports generated]
file mkdir $report_dir

create_project -in_memory -part xc7z020clg400-2
read_verilog -sv [file join $repo_dir rtl pcm_synthetic_source.sv]
read_verilog -sv [file join $repo_dir rtl pcm_axis_packer.sv]
read_verilog -sv [file join $repo_dir rtl mic_dma_pipeline.sv]
synth_design -mode out_of_context -top mic_dma_pipeline -part xc7z020clg400-2
create_clock -name pcm_clk -period 10.000 [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks pcm_clk]
report_utilization -file [file join $report_dir mic_dma_ooc_utilization.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose \
    -file [file join $report_dir mic_dma_ooc_timing.rpt]
report_drc -file [file join $report_dir mic_dma_ooc_drc.rpt]
set violations [get_drc_violations -quiet -filter {
    SEVERITY == Error || SEVERITY == {Critical Warning}
}]
if {[llength $violations] != 0} {
    error "OOC DRC contains [llength $violations] violation(s)"
}
set worst [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $worst] == 0} { error "OOC timing path missing" }
set slack [get_property SLACK [lindex $worst 0]]
if {$slack < 0.0} { error "OOC timing failed: WNS=$slack" }
puts "MIC_DMA_OOC_PASS WNS=$slack"
exit 0
