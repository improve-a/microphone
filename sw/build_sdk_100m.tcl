set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
if {[info exists ::env(MIC_HDF)] && $::env(MIC_HDF) ne ""} {
    set hdf [file normalize $::env(MIC_HDF)]
} else {
    set hdf [file join $repo_dir reports generated mic_dma.hdf]
}
if {[info exists ::env(MIC_SDK_WORKSPACE)]} {
    set workspace [file normalize $::env(MIC_SDK_WORKSPACE)]
} else {
    set workspace [file join $script_dir build sdk_workspace_100m]
}
if {![file exists $hdf]} { error "hardware definition missing: $hdf" }
setws $workspace
createhw -name mic_dma_hw -hwspec $hdf
createbsp -name mic_dma_bsp -hwproject mic_dma_hw -proc ps7_cortexa9_0 -os standalone
setlib -bsp mic_dma_bsp -lib lwip211
configbsp -bsp mic_dma_bsp phy_link_speed CONFIG_LINKSPEED100
regenbsp -bsp mic_dma_bsp
# Enable lwIP static ARP support for the bounded diagnostic bypass.  The
# generated BSP owns lwipopts.h, so apply this immediately after regeneration
# and before compiling the application/library.
set lwipopts [file join $workspace mic_dma_bsp ps7_cortexa9_0 libsrc lwip211_v1_0 src contrib ports xilinx include lwipopts.h]
set lwipopts_text [read [open $lwipopts r]]
if {[string first "ETHARP_SUPPORT_STATIC_ENTRIES" $lwipopts_text] < 0} {
    set lwipopts_file [open $lwipopts a]
    puts $lwipopts_file "\n#define ETHARP_SUPPORT_STATIC_ENTRIES 1"
    close $lwipopts_file
}
createapp -name mic_dma_app -hwproject mic_dma_hw -bsp mic_dma_bsp \
    -proc ps7_cortexa9_0 -os standalone -lang C -app {Empty Application}
configapp -app mic_dma_app -add linker-misc {-Wl,--defsym,_HEAP_SIZE=0x200000}
if {[info exists ::env(MIC_MAX_FRAMES)] && $::env(MIC_MAX_FRAMES) ne ""} {
    if {![string is integer -strict $::env(MIC_MAX_FRAMES)] || $::env(MIC_MAX_FRAMES) <= 0} {
        error "MIC_MAX_FRAMES must be a positive integer"
    }
    configapp -app mic_dma_app -add compiler-misc "-DMIC_MAX_FRAMES=$::env(MIC_MAX_FRAMES)U"
    puts "MIC_MAX_FRAMES_ASSERT=$::env(MIC_MAX_FRAMES)"
}
importsources -name mic_dma_app -path [file join $script_dir src]
importsources -name mic_dma_app -path [file join $script_dir include]
projects -build
set elf [file join $workspace mic_dma_app Debug mic_dma_app.elf]
if {![file exists $elf]} { error "SDK application build failed: $elf" }
puts "MIC_SDK_100M_BUILD_PASS"
exit 0
