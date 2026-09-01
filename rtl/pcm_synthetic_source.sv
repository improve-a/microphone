`timescale 1ns/1ps

// Synthetic substitute used until REAL_MIC_PROTOCOL_PENDING is resolved.
module pcm_synthetic_source #(
    parameter integer CHANNELS          = 8,
    parameter integer SAMPLES_PER_FRAME = 128,
    parameter integer CHANNEL_INDEX_W   = (CHANNELS <= 1) ? 1 : $clog2(CHANNELS),
    parameter integer SAMPLE_INDEX_W    =
        (SAMPLES_PER_FRAME <= 1) ? 1 : $clog2(SAMPLES_PER_FRAME)
) (
    input  wire                         clk,
    input  wire                         resetn,
    input  wire                         mode_i,  // 0: sine, 1: pseudo-signal
    input  wire [31:0]                  seed_i,
    output wire signed [15:0]           pcm_data_o,
    output wire                         pcm_valid_o,
    input  wire                         pcm_ready_i,
    output wire                         pcm_last_o,
    output wire [CHANNEL_INDEX_W-1:0]  channel_index_o,
    output wire [SAMPLE_INDEX_W-1:0]   sample_index_o,
    output wire [31:0]                  frame_index_o
);
    reg [CHANNEL_INDEX_W-1:0] channel_index;
    reg [SAMPLE_INDEX_W-1:0] sample_index;
    reg [31:0] frame_index;
    reg active;

    function automatic signed [15:0] sine_q15(input [4:0] phase);
        begin
            case (phase)
                5'd0: sine_q15=16'sd0;       5'd1: sine_q15=16'sd6393;
                5'd2: sine_q15=16'sd12539;   5'd3: sine_q15=16'sd18204;
                5'd4: sine_q15=16'sd23170;   5'd5: sine_q15=16'sd27245;
                5'd6: sine_q15=16'sd30273;   5'd7: sine_q15=16'sd32137;
                5'd8: sine_q15=16'sd32767;   5'd9: sine_q15=16'sd32137;
                5'd10: sine_q15=16'sd30273;  5'd11: sine_q15=16'sd27245;
                5'd12: sine_q15=16'sd23170;  5'd13: sine_q15=16'sd18204;
                5'd14: sine_q15=16'sd12539;  5'd15: sine_q15=16'sd6393;
                5'd16: sine_q15=16'sd0;      5'd17: sine_q15=-16'sd6393;
                5'd18: sine_q15=-16'sd12539; 5'd19: sine_q15=-16'sd18204;
                5'd20: sine_q15=-16'sd23170; 5'd21: sine_q15=-16'sd27245;
                5'd22: sine_q15=-16'sd30273; 5'd23: sine_q15=-16'sd32137;
                5'd24: sine_q15=-16'sd32768; 5'd25: sine_q15=-16'sd32137;
                5'd26: sine_q15=-16'sd30273; 5'd27: sine_q15=-16'sd27245;
                5'd28: sine_q15=-16'sd23170; 5'd29: sine_q15=-16'sd18204;
                5'd30: sine_q15=-16'sd12539; default: sine_q15=-16'sd6393;
            endcase
        end
    endfunction

    function automatic signed [15:0] pseudo_q15(
        input [31:0] index_value,
        input [31:0] seed_value
    );
        reg [31:0] value;
        begin
            value = index_value ^ seed_value;
            value = value ^ (value << 13);
            value = value ^ (value >> 17);
            value = value ^ (value << 5);
            pseudo_q15 = value[15:0];
        end
    endfunction

    function automatic signed [15:0] make_sample(
        input [31:0] frame_value,
        input integer sample_value,
        input integer channel_value,
        input mode_value,
        input [31:0] seed_value
    );
        reg [31:0] delayed_index;
        reg signed [15:0] raw;
        integer shift_value;
        begin
            if (sample_value < channel_value) begin
                make_sample = 16'sd0;
            end else begin
                delayed_index = frame_value * SAMPLES_PER_FRAME
                              + sample_value - channel_value;
                raw = mode_value ? pseudo_q15(delayed_index, seed_value)
                                 : sine_q15(delayed_index[4:0]);
                shift_value = (channel_value > 15) ? 15 : channel_value;
                make_sample = raw >>> shift_value;
            end
        end
    endfunction

    assign pcm_data_o = make_sample(
        frame_index, sample_index, channel_index, mode_i, seed_i
    );
    assign pcm_valid_o = active;
    assign pcm_last_o = (channel_index == CHANNELS - 1)
                     && (sample_index == SAMPLES_PER_FRAME - 1);
    assign channel_index_o = channel_index;
    assign sample_index_o = sample_index;
    assign frame_index_o = frame_index;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            channel_index <= {CHANNEL_INDEX_W{1'b0}};
            sample_index <= {SAMPLE_INDEX_W{1'b0}};
            frame_index <= 32'd0;
            active <= 1'b0;
        end else begin
            active <= 1'b1;
            if (active && pcm_ready_i) begin
                if (channel_index == CHANNELS - 1) begin
                    channel_index <= {CHANNEL_INDEX_W{1'b0}};
                    if (sample_index == SAMPLES_PER_FRAME - 1) begin
                        sample_index <= {SAMPLE_INDEX_W{1'b0}};
                        frame_index <= frame_index + 1'b1;
                    end else begin
                        sample_index <= sample_index + 1'b1;
                    end
                end else begin
                    channel_index <= channel_index + 1'b1;
                end
            end
        end
    end

    initial begin
        if (CHANNELS < 1) $error("CHANNELS must be positive");
        if (SAMPLES_PER_FRAME < 1) $error("SAMPLES_PER_FRAME must be positive");
    end
endmodule
