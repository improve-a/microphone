# AX7Z020 board user LEDs (user manual p.37), active low, Bank 35.
set_property PACKAGE_PIN J14 [get_ports {dbg_led_n[0]}]
set_property PACKAGE_PIN K14 [get_ports {dbg_led_n[1]}]
set_property PACKAGE_PIN J18 [get_ports {dbg_led_n[2]}]
set_property PACKAGE_PIN H18 [get_ports {dbg_led_n[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dbg_led_n[*]}]
