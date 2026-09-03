`timescale 1ns/1ps

// Vivado 2019.1 needs a Verilog top file for a block-design module
// reference; the actual probe implementation remains in pl_runtime_probe.sv.
module pl_runtime_probe_ref (
    input wire       fclk0,
    input wire       fclk_reset0_n,
    input wire       interconnect_aresetn,
    input wire       peripheral_aresetn,
    output wire [3:0] dbg_led_n
);
    pl_runtime_probe probe_i (
        .fclk0(fclk0),
        .fclk_reset0_n(fclk_reset0_n),
        .interconnect_aresetn(interconnect_aresetn),
        .peripheral_aresetn(peripheral_aresetn),
        .dbg_led_n(dbg_led_n)
    );
endmodule
