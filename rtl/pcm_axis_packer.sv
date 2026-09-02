`timescale 1ns/1ps

module pcm_axis_packer (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF M_AXIS, ASSOCIATED_RESET resetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input  wire                 clk,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME resetn, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
    input  wire                 resetn,
    input  wire signed [15:0]   pcm_data_i,
    input  wire                 pcm_valid_i,
    output wire                 pcm_ready_o,
    input  wire                 pcm_last_i,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [31:0]          m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
    output wire [3:0]           m_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire                 m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire                 m_axis_tready,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS, TDATA_NUM_BYTES 4, HAS_TKEEP 1, HAS_TLAST 1" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire                 m_axis_tlast
);
    reg [15:0] low_sample;
    reg low_valid;
    reg [31:0] data_reg;
    reg [3:0] keep_reg;
    reg last_reg;
    reg valid_reg;

    assign pcm_ready_o = !valid_reg || m_axis_tready;
    assign m_axis_tdata = data_reg;
    assign m_axis_tkeep = keep_reg;
    assign m_axis_tvalid = valid_reg;
    assign m_axis_tlast = last_reg;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            low_sample <= 16'd0;
            low_valid <= 1'b0;
            data_reg <= 32'd0;
            keep_reg <= 4'd0;
            last_reg <= 1'b0;
            valid_reg <= 1'b0;
        end else begin
            if (valid_reg && m_axis_tready)
                valid_reg <= 1'b0;

            if (pcm_valid_i && pcm_ready_o) begin
                if (!low_valid) begin
                    if (pcm_last_i) begin
                        data_reg <= {16'd0, pcm_data_i};
                        keep_reg <= 4'b0011;
                        last_reg <= 1'b1;
                        valid_reg <= 1'b1;
                    end else begin
                        low_sample <= pcm_data_i;
                        low_valid <= 1'b1;
                    end
                end else begin
                    data_reg <= {pcm_data_i, low_sample};
                    keep_reg <= 4'b1111;
                    last_reg <= pcm_last_i;
                    valid_reg <= 1'b1;
                    low_valid <= 1'b0;
                end
            end
        end
    end
endmodule

