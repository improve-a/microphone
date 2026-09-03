`timescale 1ns/1ps

module resetn_inverter (
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn_in RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire resetn_i,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 reset_o RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output wire reset_o
);
    assign reset_o = ~resetn_i;
endmodule
