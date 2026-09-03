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
set_property CONFIG.C_AUX_RESET_HIGH {1} $rst
set reset_inv [create_bd_cell -type module -reference resetn_inverter resetn_inverter_0]
set gp [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 gp0_control_interconnect]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $gp
set hp [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 hp0_memory_interconnect]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $hp
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
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
set c0 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_zero]
set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] $c0
set c1 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_one]
set_property -dict [list CONFIG.CONST_VAL {1} CONFIG.CONST_WIDTH {1}] $c1
set gpio_diag [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_diag]
set_property -dict [list CONFIG.C_GPIO_WIDTH {1} CONFIG.C_ALL_INPUTS {1}] $gpio_diag
set runtime_probe [create_bd_cell -type module -reference pl_runtime_probe_ref pl_runtime_probe_0]

connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_GP0] [get_bd_intf_pins $gp/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $gp/M00_AXI] [get_bd_intf_pins $dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $gp/M01_AXI] [get_bd_intf_pins $gpio_diag/S_AXI]
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
    $gp/ACLK $gp/S00_ACLK $gp/M00_ACLK $gp/M01_ACLK \
    $hp/ACLK $hp/S00_ACLK $hp/M00_ACLK \
    $dma/s_axi_lite_aclk $dma/m_axi_s2mm_aclk \
    $pipeline/clk $ila/clk $rst/slowest_sync_clk] {
    connect_bd_net $fclk [get_bd_pins $pin]
}
connect_bd_net [get_bd_pins $pipeline/debug_probe] [get_bd_pins $ila/probe0]
connect_bd_net [get_bd_pins $ps/FCLK_RESET0_N] [get_bd_pins $reset_inv/resetn_i]
connect_bd_net [get_bd_pins $reset_inv/reset_o] [get_bd_pins $rst/ext_reset_in]
connect_bd_net [get_bd_pins $c0/dout] [get_bd_pins $rst/aux_reset_in] [get_bd_pins $rst/mb_debug_sys_rst]
connect_bd_net [get_bd_pins $c1/dout] [get_bd_pins $rst/dcm_locked]
connect_bd_net [get_bd_pins $c0/dout] [get_bd_pins $gpio_diag/gpio_io_i]
set interconnect_resetn [get_bd_pins $rst/interconnect_aresetn]
foreach pin [list \
    $gp/ARESETN $gp/S00_ARESETN $gp/M00_ARESETN $gp/M01_ARESETN \
    $hp/ARESETN $hp/S00_ARESETN $hp/M00_ARESETN] {
    connect_bd_net $interconnect_resetn [get_bd_pins $pin]
}
set peripheral_resetn [get_bd_pins $rst/peripheral_aresetn]
connect_bd_net $peripheral_resetn [get_bd_pins $dma/axi_resetn] [get_bd_pins $pipeline/resetn]
connect_bd_net $fclk [get_bd_pins $gpio_diag/s_axi_aclk]
connect_bd_net $interconnect_resetn [get_bd_pins $gpio_diag/s_axi_aresetn]
connect_bd_net $fclk [get_bd_pins $runtime_probe/fclk0]
connect_bd_net [get_bd_pins $ps/FCLK_RESET0_N] [get_bd_pins $runtime_probe/fclk_reset0_n]
connect_bd_net $interconnect_resetn [get_bd_pins $runtime_probe/interconnect_aresetn]
connect_bd_net $peripheral_resetn [get_bd_pins $runtime_probe/peripheral_aresetn]
set runtime_led_port [create_bd_port -dir O -from 3 -to 0 dbg_led_n]
connect_bd_net [get_bd_pins $runtime_probe/dbg_led_n] $runtime_led_port

assign_bd_address -offset 0x40400000 -range 64K \
    -target_address_space [get_bd_addr_spaces $ps/Data] \
    [get_bd_addr_segs $dma/S_AXI_LITE/Reg]
assign_bd_address -offset 0x41200000 -range 4K \
    -target_address_space [get_bd_addr_spaces $ps/Data] \
    [get_bd_addr_segs $gpio_diag/S_AXI/Reg]
assign_bd_address -target_address_space [get_bd_addr_spaces $dma/Data_S2MM] \
    [get_bd_addr_segs $ps/S_AXI_HP0/HP0_DDR_LOWOCM]

validate_bd_design

# Machine assertions copied from the validated M2 DMA/DDR topology.
foreach {prop expected} {
    CONFIG.PCW_USE_M_AXI_GP0 1
    CONFIG.PCW_USE_S_AXI_HP0 1
    CONFIG.PCW_EN_DDR 1
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 50.0
} {
    set actual [get_property $prop $ps]
    if {![string equal $actual $expected] && ![string equal $actual "${expected}000000"]} {
        error "PS7 assertion failed: $prop expected=$expected actual=$actual"
    }
}
foreach {prop expected} {
    CONFIG.c_include_sg 0
    CONFIG.c_include_mm2s 0
    CONFIG.c_include_s2mm 1
    CONFIG.c_s_axis_s2mm_tdata_width 32
    CONFIG.c_sg_length_width 23
    CONFIG.c_include_s2mm_dre 0
} {
    set actual [get_property $prop $dma]
    if {![string equal $actual $expected]} {
        error "DMA assertion failed: $prop expected=$expected actual=$actual"
    }
}
set dma_map [get_bd_addr_segs -of_objects [get_bd_addr_spaces $ps/Data] -filter {NAME =~ *axi_dma_0*}]
if {[llength $dma_map] != 1} { error "DMA address segment count expected 1: $dma_map" }
set dma_offset [get_property OFFSET $dma_map]
set dma_range [get_property RANGE $dma_map]
if {$dma_offset ne "0x40400000" || ($dma_range ne "64K" && $dma_range ne "65536" && $dma_range ne "0x00010000")} {
    error "DMA address assertion failed: offset=$dma_offset range=$dma_range"
}
proc assert_one_net {pin label} {
    set nets [get_bd_nets -of_objects [get_bd_pins $pin]]
    if {[llength $nets] != 1} { error "$label clock/reset net count expected 1: $nets" }
}
foreach {pin label} [list \
    $ps/FCLK_CLK0 PS_FCLK0 \
    $ps/M_AXI_GP0_ACLK PS_GP0_ACLK \
    $ps/S_AXI_HP0_ACLK PS_HP0_ACLK \
    $dma/s_axi_lite_aclk DMA_AXIL_CLK \
    $dma/m_axi_s2mm_aclk DMA_S2MM_CLK \
    $rst/interconnect_aresetn RESET_INTERCONNECT \
    $rst/peripheral_aresetn RESET_PERIPHERAL \
    $dma/axi_resetn DMA_RESET \
    $pipeline/resetn PIPELINE_RESET] { assert_one_net $pin $label }
set runtime_led_ports [get_bd_ports -quiet dbg_led_n]
if {[llength $runtime_led_ports] != 1} { error "runtime probe LED port count expected 1: $runtime_led_ports" }
if {[get_property LEFT $runtime_led_ports] != 3 || [get_property RIGHT $runtime_led_ports] != 0} {
    error "runtime probe LED port width expected [3:0]: [get_property LEFT $runtime_led_ports]:[get_property RIGHT $runtime_led_ports]"
}
foreach {pin label} [list \
    $runtime_probe/fclk0 RUNTIME_PROBE_FCLK0 \
    $runtime_probe/fclk_reset0_n RUNTIME_PROBE_FCLK_RESET0_N \
    $runtime_probe/interconnect_aresetn RUNTIME_PROBE_INTERCONNECT_RESET \
    $runtime_probe/peripheral_aresetn RUNTIME_PROBE_PERIPHERAL_RESET] { assert_one_net $pin $label }
foreach {pin label} [list \
    $ps/M_AXI_GP0 GP0_INTERFACE \
    $gp/M00_AXI GP0_TO_DMA \
    $pipeline/M_AXIS PIPELINE_TO_DMA \
    $dma/M_AXI_S2MM DMA_TO_HP0 \
    $hp/M00_AXI HP0_TO_PS] {
    set nets [get_bd_intf_nets -of_objects [get_bd_intf_pins $pin]]
    if {[llength $nets] != 1} { error "$label interface net count expected 1: $nets" }
}
puts "MIC_M2_CLOCK_RESET_ASSERT_PASS"
puts "MIC_M2_DMA_CONFIG_ASSERT_PASS"
puts "MIC_M2_ADDRESS_ASSERT_PASS DMA=$dma_offset RANGE=$dma_range"
save_bd_design
