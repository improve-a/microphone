`timescale 1ns / 1ps

module pl_runtime_probe (
    input  wire       fclk0,
    input  wire       fclk_reset0_n,
    input  wire       interconnect_aresetn,
    input  wire       peripheral_aresetn,
    output wire [3:0] dbg_led_n
);
    // This counter intentionally runs independently of proc_sys_reset so it
    // distinguishes a missing FCLK from a reset output that remains asserted.
    reg [25:0] heartbeat_counter = 26'd0;

    always @(posedge fclk0) begin
        heartbeat_counter <= heartbeat_counter + 1'b1;
    end

    // The board LEDs are active low.
    assign dbg_led_n[0] = heartbeat_counter[24];
    assign dbg_led_n[1] = ~interconnect_aresetn;
    assign dbg_led_n[2] = ~peripheral_aresetn;
    assign dbg_led_n[3] = ~fclk_reset0_n;
endmodule
