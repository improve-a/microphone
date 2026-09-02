set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
set ps_config [file join [file dirname [file normalize [info script]]] ax7z020_ps7_properties.tcl]
source -notrace $ps_config
if {![info exists m0_ps7_properties]} { error "AX7Z020 PS7 property source missing: $ps_config" }
set_property -dict $m0_ps7_properties $ps
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50.0}] $ps

make_bd_intf_pins_external [get_bd_intf_pins $ps/DDR]
set_property name DDR [get_bd_intf_ports DDR_0]
make_bd_intf_pins_external [get_bd_intf_pins $ps/FIXED_IO]
set_property name FIXED_IO [get_bd_intf_ports FIXED_IO_0]

set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0]
set reset_inv [create_bd_cell -type module -reference resetn_inverter resetn_inverter_0]
set gp [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 gp0_control_interconnect]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $gp
set hp [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 hp0_memory_interconnect]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $hp
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_sg_length_width {23} \
    CONFIG.c_include_s2mm_dre {0}] $dma
set pipeline [create_bd_cell -type module -reference mic_dma_pipeline_ref mic_dma_pipeline_0]
set source_mode 0
if {[info exists ::env(MIC_SOURCE_MODE)] && $::env(MIC_SOURCE_MODE) ne ""} {
    set source_mode $::env(MIC_SOURCE_MODE)
}
set_property -dict [list \
    CONFIG.CHANNELS {8} \
    CONFIG.SAMPLES_PER_FRAME {128} \
    CONFIG.SOURCE_MODE $source_mode \
    CONFIG.SOURCE_SEED {0x13579BDF}] $pipeline
set ila [create_bd_cell -type ip -vlnv xilinx.com:ip:ila:6.2 ila_0]
set_property -dict [list CONFIG.C_NUM_OF_PROBES {1} CONFIG.C_PROBE0_WIDTH {256} CONFIG.C_DATA_DEPTH {1024}] $ila
set irqcat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat]
set_property CONFIG.NUM_PORTS {1} $irqcat

connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_GP0] [get_bd_intf_pins $gp/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $gp/M00_AXI] [get_bd_intf_pins $dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $pipeline/M_AXIS] [get_bd_intf_pins $dma/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXI_S2MM] [get_bd_intf_pins $hp/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $hp/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP0]
connect_bd_net [get_bd_pins $dma/s2mm_introut] [get_bd_pins $irqcat/In0]
connect_bd_net [get_bd_pins $irqcat/dout] [get_bd_pins $ps/IRQ_F2P]
foreach {pin name} [list \
    $pipeline/mic_d0 mic_d0 $pipeline/mic_d1 mic_d1 \
    $pipeline/mic_d2 mic_d2 $pipeline/mic_d3 mic_d3 \
    $pipeline/mic_bck mic_bck $pipeline/mic_ws mic_ws] {
    make_bd_pins_external [get_bd_pins $pin]
    set ext [lindex [get_bd_ports -of_objects [get_bd_pins $pin]] 0]
    if {$ext ne ""} { set_property name $name $ext }
}

set fclk [get_bd_pins $ps/FCLK_CLK0]
foreach pin [list \
    $ps/M_AXI_GP0_ACLK $ps/S_AXI_HP0_ACLK \
    $gp/ACLK $gp/S00_ACLK $gp/M00_ACLK \
    $hp/ACLK $hp/S00_ACLK $hp/M00_ACLK \
    $dma/s_axi_lite_aclk $dma/m_axi_s2mm_aclk \
    $pipeline/clk $ila/clk $rst/slowest_sync_clk] {
    connect_bd_net $fclk [get_bd_pins $pin]
}
connect_bd_net [get_bd_pins $pipeline/debug_probe] [get_bd_pins $ila/probe0]
connect_bd_net [get_bd_pins $ps/FCLK_RESET0_N] [get_bd_pins $reset_inv/resetn_i]
connect_bd_net [get_bd_pins $reset_inv/reset_o] [get_bd_pins $rst/ext_reset_in]
set resetn [get_bd_pins $rst/peripheral_aresetn]
foreach pin [list \
    $gp/ARESETN $gp/S00_ARESETN $gp/M00_ARESETN \
    $hp/ARESETN $hp/S00_ARESETN $hp/M00_ARESETN \
    $dma/axi_resetn $pipeline/resetn] {
    connect_bd_net $resetn [get_bd_pins $pin]
}

assign_bd_address -offset 0x40400000 -range 64K \
    -target_address_space [get_bd_addr_spaces $ps/Data] \
    [get_bd_addr_segs $dma/S_AXI_LITE/Reg]
assign_bd_address -target_address_space [get_bd_addr_spaces $dma/Data_S2MM] \
    [get_bd_addr_segs $ps/S_AXI_HP0/HP0_DDR_LOWOCM]

validate_bd_design
save_bd_design
