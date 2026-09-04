set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set hdf [file join $repo_dir reports generated mic_dma.hdf]
if {[info exists ::env(MIC_SDK_WORKSPACE)]} {
    set workspace [file normalize $::env(MIC_SDK_WORKSPACE)]
} else {
    set workspace [file join $script_dir build sdk_workspace]
}
if {![file exists $hdf]} { error "hardware definition missing: $hdf" }
setws $workspace
createhw -name mic_dma_hw -hwspec $hdf
createbsp -name mic_dma_bsp -hwproject mic_dma_hw -proc ps7_cortexa9_0 -os standalone
setlib -bsp mic_dma_bsp -lib lwip211
# The AX7Z020 carrier PHY at MDIO address 3 is not one of the IDs recognized
# by SDK 2019.1. The connected Windows adapter negotiates a physical 1 Gb/s
# link, so avoid the adapter's invalid zero-speed autodetect result.
configbsp -bsp mic_dma_bsp phy_link_speed CONFIG_LINKSPEED1000
regenbsp -bsp mic_dma_bsp
createapp -name mic_dma_app -hwproject mic_dma_hw -bsp mic_dma_bsp \
    -proc ps7_cortexa9_0 -os standalone -lang C -app {Empty Application}
# lwIP's GEM RX/TX rings are allocated from the application heap.
configapp -app mic_dma_app -add linker-misc {-Wl,--defsym,_HEAP_SIZE=0x200000}
importsources -name mic_dma_app -path [file join $script_dir src]
importsources -name mic_dma_app -path [file join $script_dir include]
projects -build
set elf [file join $workspace mic_dma_app Debug mic_dma_app.elf]
if {![file exists $elf]} { error "SDK application build failed: $elf" }
puts "MIC_SDK_BUILD_PASS"
exit 0
