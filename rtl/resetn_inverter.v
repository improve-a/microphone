`timescale 1ns/1ps

module resetn_inverter (
    input wire resetn_i,
    output wire reset_o
);
    assign reset_o = ~resetn_i;
endmodule

