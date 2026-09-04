open_project [lindex $argv 0]
open_run impl_1
puts "MIC_NETLIST_PROJECT=[lindex $argv 0]"
foreach path {
    mic_dma_system_i/axi_dma_0/s_axi_lite_aclk
    mic_dma_system_i/axi_dma_0/m_axi_s2mm_aclk
    mic_dma_system_i/axi_dma_0/axi_resetn
    mic_dma_system_i/gp0_control_interconnect/ACLK
    mic_dma_system_i/gp0_control_interconnect/ARESETN
    mic_dma_system_i/hp0_memory_interconnect/ACLK
    mic_dma_system_i/hp0_memory_interconnect/ARESETN
    mic_dma_system_i/proc_sys_reset_0/interconnect_aresetn
    mic_dma_system_i/proc_sys_reset_0/peripheral_aresetn
} {
    set p [get_pins -quiet $path]
    if {[llength $p] != 1} { puts "MIC_NETLIST_PIN_MISSING=$path"; continue }
    set n [get_nets -of_objects $p]
    puts "MIC_NETLIST_PIN=$path NET=$n DRIVERS=[llength [get_pins -of_objects $n -filter {DIRECTION == OUT}]] LOADS=[llength [get_pins -of_objects $n -filter {DIRECTION == IN}]]"
}
foreach pattern {"*gp0_control_interconnect*ACLK" "*gp0_control_interconnect*ARESETN" "*hp0_memory_interconnect*ACLK" "*hp0_memory_interconnect*ARESETN"} {
    foreach p [get_pins -hier -quiet -filter "NAME =~ $pattern"] {
        set n [get_nets -of_objects $p]
        puts "MIC_NETLIST_WILDCARD_PIN=$p NET=$n"
    }
}
foreach path {
    mic_dma_system_i/gp0_control_interconnect/M00_AXI_awvalid
    mic_dma_system_i/gp0_control_interconnect/M00_AXI_awready
    mic_dma_system_i/gp0_control_interconnect/M00_AXI_wvalid
    mic_dma_system_i/gp0_control_interconnect/M00_AXI_wready
    mic_dma_system_i/gp0_control_interconnect/M00_AXI_bvalid
} {
    set p [get_pins -quiet $path]
    if {[llength $p] != 1} { puts "MIC_NETLIST_AXI_PIN_MISSING=$path"; continue }
    set n [get_nets -of_objects $p]
    puts "MIC_NETLIST_AXI_PIN=$path NET=$n DRIVERS=[llength [get_pins -of_objects $n -filter {DIRECTION == OUT}]] LOADS=[llength [get_pins -of_objects $n -filter {DIRECTION == IN}]]"
}
puts "MIC_NETLIST_DMA_CELL=[get_cells -quiet mic_dma_system_i/axi_dma_0]"
exit 0
