# Read-only Vivado Hardware Manager probe for AX7Z020 bring-up.
puts "MIC_VIVADO_EXECUTABLE=[info nameofexecutable]"
puts "MIC_VIVADO_VERSION=[version]"
puts "MIC_OPEN_HW_MANAGER_COMMANDS=[info commands open_hw_manager]"
catch {load_features hw_manager}
catch {load_features labtools}
puts "MIC_OPEN_HW_MANAGER_COMMANDS_AFTER_LOAD=[info commands open_hw_manager]"
if {[llength [info commands open_hw_manager]] == 0} {
    puts "MIC_JTAG_PROBE_FAIL hardware-manager-feature-unavailable"
    exit 4
}
open_hw_manager
connect_hw_server -url localhost:3121
set servers [get_hw_servers]
puts "HW_SERVERS=[llength $servers]"
set targets [get_hw_targets -quiet]
puts "HW_TARGETS=[llength $targets]"
foreach target $targets {
    puts "TARGET=$target"
    catch {puts "TARGET_NAME=[get_property NAME $target]"}
    catch {puts "TARGET_STATE=[get_property STATE $target]"}
}
if {[llength $targets] == 0} {
    puts "MIC_JTAG_PROBE_FAIL no hardware targets"
    exit 2
}
set target [lindex $targets 0]
current_hw_target $target
open_hw_target
set devices [get_hw_devices -quiet]
puts "HW_DEVICES=[llength $devices]"
foreach device $devices {
    puts "DEVICE=$device"
    catch {puts "DEVICE_NAME=[get_property NAME $device]"}
    catch {puts "DEVICE_PART=[get_property PART $device]"}
    catch {puts "DEVICE_STATE=[get_property STATE $device]"}
}
if {[llength $devices] == 0} {
    puts "MIC_JTAG_PROBE_FAIL no hardware devices"
    close_hw_target
    disconnect_hw_server
    close_hw_manager
    exit 3
}
puts "MIC_JTAG_PROBE_PASS"
close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
