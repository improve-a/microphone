`timescale 1ns/1ps

// REAL_MIC_PROTOCOL_PENDING
// Deliberately has no GPIO pins or protocol logic. Replace this shell only
// after the microphone datasheet, schematic, I/O voltage, clocking, edge and
// channel topology are confirmed.
module real_mic_frontend_pending #(
    parameter integer CHANNELS = 8
) (
    input  wire clk,
    input  wire resetn,
    output wire signed [15:0] pcm_data_o,
    output wire pcm_valid_o,
    input  wire pcm_ready_i,
    output wire pcm_last_o
);
    assign pcm_data_o = 16'sd0;
    assign pcm_valid_o = 1'b0;
    assign pcm_last_o = 1'b0;
endmodule

