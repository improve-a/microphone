set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set build_root [file join $script_dir build rtl_tests]
file mkdir $build_root

proc run_test {repo_dir build_root top pass_token final_test sources} {
    set project_dir [file join $build_root $top]
    create_project -force $top $project_dir -part xc7z020clg400-2
    foreach source $sources {
        add_files -norecurse [file join $repo_dir $source]
    }
    set_property top $top [get_filesets sim_1]
    set_property top_lib xil_defaultlib [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation
    run all
    if {$final_test} {
        after 1000
    } else {
        close_sim
    }
    set sim_log [file join $project_dir "$top.sim" sim_1 behav xsim simulate.log]
    if {![file exists $sim_log]} {
        error "simulation log missing for $top"
    }
    set handle [open $sim_log r]
    set contents [read $handle]
    close $handle
    if {!$final_test} { close_project }
    if {[string first $pass_token $contents] < 0} {
        error "$top did not emit required token $pass_token"
    }
    if {[regexp {Fatal:|_FAIL|\mERROR\M} $contents]} {
        error "$top simulation log contains a failure marker"
    }
    puts "RTL_TEST_PASS top=$top"
}

run_test $repo_dir $build_root tb_pcm_synthetic_source MIC_FRONTEND_RTL_PASS false [list \
    rtl/pcm_synthetic_source.sv \
    tb/tb_pcm_synthetic_source.sv]

run_test $repo_dir $build_root tb_pcm_axis_packer MIC_PACKER_RTL_PASS true [list \
    rtl/pcm_axis_packer.sv \
    tb/tb_pcm_axis_packer.sv]

puts "MIC_RTL_SUITE_PASS"
exit 0
