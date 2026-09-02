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
createapp -name mic_dma_app -hwproject mic_dma_hw -bsp mic_dma_bsp \
    -proc ps7_cortexa9_0 -os standalone -lang C -app {Empty Application}
importsources -name mic_dma_app -path [file join $script_dir src]
importsources -name mic_dma_app -path [file join $script_dir include]
projects -build
puts "MIC_SDK_BUILD_PASS"
exit 0
