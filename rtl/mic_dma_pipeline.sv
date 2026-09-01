`timescale 1ns/1ps

module mic_dma_pipeline #(
    parameter integer CHANNELS = 8,
    parameter integer SAMPLES_PER_FRAME = 128,
    parameter integer SOURCE_MODE = 0,
    parameter [31:0] SOURCE_SEED = 32'h13579BDF
) (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF M_AXIS, ASSOCIATED_RESET resetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input  wire        clk,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME resetn, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
    input  wire        resetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [31:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
    output wire [3:0]  m_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire        m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire        m_axis_tready,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS, TDATA_NUM_BYTES 4, HAS_TKEEP 1, HAS_TLAST 1" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire        m_axis_tlast
);
    wire signed [15:0] pcm_data;
    wire pcm_valid;
    wire pcm_ready;
    wire pcm_last;

    pcm_synthetic_source #(
        .CHANNELS(CHANNELS),
        .SAMPLES_PER_FRAME(SAMPLES_PER_FRAME)
    ) source (
        .clk(clk),
        .resetn(resetn),
        .mode_i(SOURCE_MODE != 0),
        .seed_i(SOURCE_SEED),
        .pcm_data_o(pcm_data),
        .pcm_valid_o(pcm_valid),
        .pcm_ready_i(pcm_ready),
        .pcm_last_o(pcm_last),
        .channel_index_o(),
        .sample_index_o(),
        .frame_index_o()
    );

    pcm_axis_packer packer (
        .clk(clk),
        .resetn(resetn),
        .pcm_data_i(pcm_data),
        .pcm_valid_i(pcm_valid),
        .pcm_ready_o(pcm_ready),
        .pcm_last_i(pcm_last),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );
endmodule

