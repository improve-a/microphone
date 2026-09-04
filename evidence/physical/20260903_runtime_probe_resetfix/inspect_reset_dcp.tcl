open_checkpoint {D:/microphone/vivado/build/mic_dma_runtime_probe_resetfix_20260903/mic_dma.runs/impl_1/mic_dma_system_wrapper_routed.dcp}
puts "MIC_DCP_TOP=[get_property top [current_design]]"
foreach p {
  mic_dma_system_i/processing_system7_0/FCLK_CLK0
  mic_dma_system_i/processing_system7_0/FCLK_RESET0_N
  mic_dma_system_i/resetn_inverter_0/resetn_i
  mic_dma_system_i/resetn_inverter_0/reset_o
  mic_dma_system_i/proc_sys_reset_0/slowest_sync_clk
  mic_dma_system_i/proc_sys_reset_0/ext_reset_in
  mic_dma_system_i/proc_sys_reset_0/dcm_locked
  mic_dma_system_i/proc_sys_reset_0/interconnect_aresetn
  mic_dma_system_i/proc_sys_reset_0/peripheral_aresetn
} {
  set pins [get_pins -quiet $p]
  if {[llength $pins]} {
    set nets [get_nets -quiet -of_objects $pins]
    puts "MIC_DCP_PIN $p NETS=$nets"
  } else {
    puts "MIC_DCP_PIN_MISSING $p"
  }
}
foreach c [get_cells -hier -filter {REF_NAME == FDRE}] {
  if {[string match *proc_sys_reset* $c]} {
    puts "MIC_DCP_RESET_FF $c INIT=[get_property INIT $c] D=[get_nets -quiet -of_objects [get_pins -quiet $c/D]] Q=[get_nets -quiet -of_objects [get_pins -quiet $c/Q]]"
  }
}
foreach c [get_cells -hier -filter {REF_NAME =~ SRL16*}] {
  if {[string match *proc_sys_reset* $c]} {
    puts "MIC_DCP_RESET_SRL $c REF=[get_property REF_NAME $c] INIT=[get_property INIT $c]"
  }
}
foreach c [get_cells -hier -filter {NAME =~ *resetn_inverter*}] {
  puts "MIC_DCP_RESET_INV_CELL $c REF=[get_property REF_NAME $c] INIT=[get_property INIT $c]"
}
report_drc -file {D:/microphone/evidence/physical/20260903_runtime_probe_resetfix/reset_dcp_drc.rpt}
close_design
exit
