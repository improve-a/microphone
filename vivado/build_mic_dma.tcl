set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set build_leaf mic_dma
if {[info exists ::env(MIC_VIVADO_BUILD_LEAF)] && $::env(MIC_VIVADO_BUILD_LEAF) ne ""} {
    set build_leaf $::env(MIC_VIVADO_BUILD_LEAF)
}
set build_dir [file join $script_dir build $build_leaf]
set report_dir [file join $repo_dir reports generated]
file mkdir $build_dir
file mkdir $report_dir

create_project -force mic_dma $build_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
add_files -norecurse [list \
    [file join $repo_dir rtl pcm_synthetic_source.sv] \
    [file join $repo_dir rtl lc_ai_k210_7mic_frontend.sv] \
    [file join $repo_dir rtl pcm_axis_packer.sv] \
    [file join $repo_dir rtl mic_dma_pipeline.sv] \
    [file join $repo_dir rtl mic_dma_pipeline_ref.v] \
    [file join $repo_dir rtl resetn_inverter.v]]
add_files -fileset constrs_1 -norecurse [file join $repo_dir vivado lc_ai_k210_7mic.xdc]
update_compile_order -fileset sources_1
create_bd_design mic_dma_system
source [file join $script_dir create_mic_dma_bd.tcl]
puts "MIC_DMA_BD_VALIDATION_PASS"

generate_target all [get_files [file join $build_dir mic_dma.srcs sources_1 bd mic_dma_system mic_dma_system.bd]]
make_wrapper -files [get_files [file join $build_dir mic_dma.srcs sources_1 bd mic_dma_system mic_dma_system.bd]] -top
add_files -norecurse [file join $build_dir mic_dma.srcs sources_1 bd mic_dma_system hdl mic_dma_system_wrapper.v]
set_property top mic_dma_system_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%" ||
    [get_property STATUS [get_runs synth_1]] ni {"synth_design Complete!" "Complete"}} {
    error "synthesis did not complete: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1
report_utilization -file [file join $report_dir mic_dma_synth_utilization.rpt]
report_drc -file [file join $report_dir mic_dma_synth_drc.rpt]
write_hwdef -force -file [file join $report_dir mic_dma.hdf]
close_design

launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%" ||
    [get_property STATUS [get_runs impl_1]] ni {"write_bitstream Complete!" "route_design Complete!" "Complete"}} {
    error "implementation did not complete: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
report_utilization -file [file join $report_dir mic_dma_impl_utilization.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose \
    -file [file join $report_dir mic_dma_impl_timing.rpt]
report_drc -file [file join $report_dir mic_dma_impl_drc.rpt]
set critical_drc [get_drc_violations -quiet -filter {IS_ENABLED && (SEVERITY == Error || SEVERITY == Critical Warning)}]
if {[llength $critical_drc] != 0} {
    error "implementation has [llength $critical_drc] critical DRC violation(s)"
}
set worst [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $worst] == 0} { error "implementation timing path missing" }
set slack [get_property SLACK [lindex $worst 0]]
if {$slack < 0.0} { error "implementation timing failed: WNS=$slack" }
puts "MIC_DMA_IMPLEMENTATION_PASS WNS=$slack"
puts "MIC_DMA_VIVADO_PASS"
exit 0
