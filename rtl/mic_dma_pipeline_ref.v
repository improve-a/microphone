`timescale 1ns/1ps

// Vivado 2019.1 requires a Verilog top file for block-design module references.
module mic_dma_pipeline_ref #(
    parameter integer CHANNELS = 8,
    parameter integer SAMPLES_PER_FRAME = 128,
    parameter integer SOURCE_MODE = 0,
    parameter [31:0] SOURCE_SEED = 32'h13579BDF
) (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF M_AXIS, ASSOCIATED_RESET resetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input wire clk,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME resetn, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
    input wire resetn,
    input wire mic_d0,
    input wire mic_d1,
    input wire mic_d2,
    input wire mic_d3,
    output wire mic_bck,
    output wire mic_ws,
    output wire [255:0] debug_probe,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [31:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
    output wire [3:0] m_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input wire m_axis_tready,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS, TDATA_NUM_BYTES 4, HAS_TKEEP 1, HAS_TLAST 1" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire m_axis_tlast
);
    mic_dma_pipeline #(
        .CHANNELS(CHANNELS),
        .SAMPLES_PER_FRAME(SAMPLES_PER_FRAME),
        .SOURCE_MODE(SOURCE_MODE),
        .SOURCE_SEED(SOURCE_SEED)
    ) core (
        .clk(clk), .resetn(resetn),
        .mic_d0(mic_d0), .mic_d1(mic_d1), .mic_d2(mic_d2), .mic_d3(mic_d3),
        .mic_bck(mic_bck), .mic_ws(mic_ws), .debug_probe(debug_probe),
        .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );
endmodule
