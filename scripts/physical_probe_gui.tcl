start_gui
after 3000
puts "GUI_COMMANDS_OPEN_HW_MANAGER=[llength [info commands open_hw_manager]]"
if {[llength [info commands open_hw_manager]] == 0} { exit 4 }
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets -quiet]
puts "GUI_HW_TARGET_COUNT=[llength $targets]"
foreach target $targets { puts "GUI_TARGET=$target" }
if {[llength $targets] == 0} { exit 5 }
current_hw_target [lindex $targets 0]
open_hw_target
set devices [get_hw_devices -quiet]
puts "GUI_HW_DEVICE_COUNT=[llength $devices]"
foreach device $devices { puts "GUI_DEVICE=$device" }
puts "MIC_GUI_HW_PROBE_PASS"
exit 0
