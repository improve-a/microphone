set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
set repo_dir [file dirname $script_dir]
set build_root [file join $script_dir build rtl_tests]
file mkdir $build_root

proc test_sources {top} {
    switch -- $top {
        tb_pcm_synthetic_source {
            return [list rtl/pcm_synthetic_source.sv tb/tb_pcm_synthetic_source.sv]
        }
        tb_pcm_axis_packer {
            return [list rtl/pcm_axis_packer.sv tb/tb_pcm_axis_packer.sv]
        }
        tb_lc_ai_k210_7mic_frontend {
            return [list rtl/lc_ai_k210_7mic_frontend.sv tb/tb_lc_ai_k210_7mic_frontend.sv]
        }
        default { error "unknown RTL test top: $top" }
    }
}

proc test_token {top} {
    switch -- $top {
        tb_pcm_synthetic_source { return MIC_FRONTEND_RTL_PASS }
        tb_pcm_axis_packer { return MIC_PACKER_RTL_PASS }
        tb_lc_ai_k210_7mic_frontend { return MIC_I2S_SCALE_RTL_PASS }
        default { error "unknown RTL test top: $top" }
    }
}

proc run_one {repo_dir build_root top} {
    set project_dir [file join $build_root $top]
    create_project -force $top $project_dir -part xc7z020clg400-2
    foreach source [test_sources $top] {
        add_files -norecurse [file join $repo_dir $source]
    }
    set_property top $top [get_filesets sim_1]
    set_property top_lib xil_defaultlib [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation
    run all
    after 1000
    puts "RTL_CHILD_COMPLETE top=$top"
}

# Vivado 2019.1 can hang in close_sim after a finished xsim session. Run each
# test in a child Vivado process so normal process teardown closes the simulator.
if {$argc == 1} {
    run_one $repo_dir $build_root [lindex $argv 0]
    exit 0
}

set vivado [info nameofexecutable]
foreach top {tb_pcm_synthetic_source tb_pcm_axis_packer tb_lc_ai_k210_7mic_frontend} {
    if {[catch {
        exec $vivado -mode batch -nolog -nojournal -source $script_path -tclargs $top 2>@1
    } output]} {
        puts $output
        error "RTL child test failed: $top"
    }
    puts $output
    set pass_token [test_token $top]
    if {[string first $pass_token $output] < 0 ||
        [string first "RTL_CHILD_COMPLETE top=$top" $output] < 0} {
        error "$top did not emit required completion tokens"
    }
    if {[regexp {Fatal:|_FAIL|\mERROR\M} $output]} {
        error "$top output contains a failure marker"
    }
    puts "RTL_TEST_PASS top=$top"
}
puts "MIC_RTL_SUITE_PASS"
exit 0
