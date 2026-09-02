`timescale 1ns/1ps

// Physical LC-AI-K210-7Mic I2S receiver.
// The initial AX7Z020 clock plan uses FCLK0=50 MHz, BCK=50 MHz/16=3.125 MHz
// and WS=BCK/64=48.828125 kHz. PCM16 uses the upper 16 bits of each 32-bit
// slot until an ILA capture confirms the module's exact valid-bit alignment.
module lc_ai_k210_7mic_frontend #(
    parameter integer SAMPLES_PER_FRAME = 128,
    parameter integer BCK_HALF_DIV      = 8,
    parameter integer SAMPLE_INDEX_W    = (SAMPLES_PER_FRAME <= 1) ? 1 : $clog2(SAMPLES_PER_FRAME)
) (
    input  wire                         clk,
    input  wire                         resetn,
    input  wire                         mic_d0,
    input  wire                         mic_d1,
    input  wire                         mic_d2,
    input  wire                         mic_d3,
    output wire                         mic_bck,
    output wire                         mic_ws,
    output reg signed [15:0]             pcm_data_o,
    output wire                         pcm_valid_o,
    input  wire                         pcm_ready_i,
    output wire                         pcm_last_o,
    output wire [2:0]                   channel_index_o,
    output wire [SAMPLE_INDEX_W-1:0]    sample_index_o,
    output wire [31:0]                  frame_index_o,
    output reg [255:0]                   debug_probe_o
);
    localparam integer DIV_W = (BCK_HALF_DIV <= 2) ? 1 : $clog2(BCK_HALF_DIV);

    (* ASYNC_REG = "TRUE" *) reg d0_meta, d1_meta, d2_meta, d3_meta;
    (* ASYNC_REG = "TRUE" *) reg d0_sync, d1_sync, d2_sync, d3_sync;
    reg [DIV_W-1:0] div_count;
    reg bck_reg;
    reg ws_reg;
    reg [5:0] bit_in_slot;
    reg slot_done_pending;
    reg [31:0] shift0, shift1, shift2, shift3;
    reg [31:0] left0, left1, left2, left3;
    reg [31:0] right0, right1, right2, right3;
    reg signed [15:0] frame_ch0, frame_ch1, frame_ch2, frame_ch3;
    reg signed [15:0] frame_ch4, frame_ch5, frame_ch6, frame_ch7;
    reg frame_ready;
    reg out_active;
    reg [2:0] out_channel;
    reg [SAMPLE_INDEX_W-1:0] pending_sample_index;
    reg [31:0] pending_frame_index;
    reg [SAMPLE_INDEX_W-1:0] sample_index;
    reg [31:0] frame_index;
    reg frame_sync_pulse;
    reg error_flag;
    reg [31:0] error_count;

    assign mic_bck = bck_reg;
    assign mic_ws = ws_reg;
    assign pcm_valid_o = out_active;
    assign pcm_last_o = out_active && (out_channel == 3'd7) &&
                        (pending_sample_index == SAMPLES_PER_FRAME - 1);
    assign channel_index_o = out_channel;
    assign sample_index_o = pending_sample_index;
    assign frame_index_o = pending_frame_index;

    always @* begin
        case (out_channel)
            3'd0: pcm_data_o = frame_ch0;
            3'd1: pcm_data_o = frame_ch1;
            3'd2: pcm_data_o = frame_ch2;
            3'd3: pcm_data_o = frame_ch3;
            3'd4: pcm_data_o = frame_ch4;
            3'd5: pcm_data_o = frame_ch5;
            3'd6: pcm_data_o = frame_ch6;
            default: pcm_data_o = frame_ch7;
        endcase
    end

    always @* begin
        debug_probe_o = 256'd0;
        debug_probe_o[0] = bck_reg;
        debug_probe_o[1] = ws_reg;
        debug_probe_o[2] = d0_sync;
        debug_probe_o[3] = d1_sync;
        debug_probe_o[4] = d2_sync;
        debug_probe_o[5] = d3_sync;
        debug_probe_o[6] = frame_sync_pulse;
        debug_probe_o[7] = error_flag;
        debug_probe_o[13:8] = bit_in_slot;
        debug_probe_o[14] = ws_reg;
        debug_probe_o[15] = frame_ready;
        debug_probe_o[16] = out_active;
        debug_probe_o[48:17] = shift0;
        debug_probe_o[80:49] = shift1;
        debug_probe_o[112:81] = shift2;
        debug_probe_o[144:113] = shift3;
        debug_probe_o[176:145] = frame_index;
        debug_probe_o[208:177] = sample_index;
        debug_probe_o[215:208] = {5'd0, out_channel};
        debug_probe_o[247:216] = error_count;
    end

    // The module data outputs are synchronous to SCK. Two flip-flops keep the
    // input pins out of the 50 MHz control logic's metastability window.
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            d0_meta <= 1'b0; d0_sync <= 1'b0;
            d1_meta <= 1'b0; d1_sync <= 1'b0;
            d2_meta <= 1'b0; d2_sync <= 1'b0;
            d3_meta <= 1'b0; d3_sync <= 1'b0;
        end else begin
            d0_meta <= mic_d0; d0_sync <= d0_meta;
            d1_meta <= mic_d1; d1_sync <= d1_meta;
            d2_meta <= mic_d2; d2_sync <= d2_meta;
            d3_meta <= mic_d3; d3_sync <= d3_meta;
        end
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            div_count <= {DIV_W{1'b0}};
            bck_reg <= 1'b0;
            ws_reg <= 1'b0;
            bit_in_slot <= 6'd0;
            slot_done_pending <= 1'b0;
            shift0 <= 32'd0; shift1 <= 32'd0;
            shift2 <= 32'd0; shift3 <= 32'd0;
            left0 <= 32'd0; left1 <= 32'd0;
            left2 <= 32'd0; left3 <= 32'd0;
            right0 <= 32'd0; right1 <= 32'd0;
            right2 <= 32'd0; right3 <= 32'd0;
            frame_ch0 <= 16'sd0; frame_ch1 <= 16'sd0;
            frame_ch2 <= 16'sd0; frame_ch3 <= 16'sd0;
            frame_ch4 <= 16'sd0; frame_ch5 <= 16'sd0;
            frame_ch6 <= 16'sd0; frame_ch7 <= 16'sd0;
            frame_ready <= 1'b0;
            out_active <= 1'b0;
            out_channel <= 3'd0;
            pending_sample_index <= {SAMPLE_INDEX_W{1'b0}};
            pending_frame_index <= 32'd0;
            sample_index <= {SAMPLE_INDEX_W{1'b0}};
            frame_index <= 32'd0;
            frame_sync_pulse <= 1'b0;
            error_flag <= 1'b0;
            error_count <= 32'd0;
        end else begin
            frame_sync_pulse <= 1'b0;

            if (!out_active && frame_ready) begin
                out_active <= 1'b1;
                out_channel <= 3'd0;
            end else if (out_active && pcm_ready_i) begin
                if (out_channel == 3'd7) begin
                    out_active <= 1'b0;
                    frame_ready <= 1'b0;
                end else begin
                    out_channel <= out_channel + 1'b1;
                end
            end

            if (div_count == BCK_HALF_DIV - 1) begin
                div_count <= {DIV_W{1'b0}};
                if (!bck_reg) begin
                    // Rising BCK edge: capture one raw bit from every bus.
                    bck_reg <= 1'b1;
                    shift0 <= {shift0[30:0], d0_sync};
                    shift1 <= {shift1[30:0], d1_sync};
                    shift2 <= {shift2[30:0], d2_sync};
                    shift3 <= {shift3[30:0], d3_sync};
                    if (bit_in_slot == 6'd31) begin
                        bit_in_slot <= 6'd0;
                        slot_done_pending <= 1'b1;
                        if (ws_reg == 1'b0) begin
                            left0 <= {shift0[30:0], d0_sync};
                            left1 <= {shift1[30:0], d1_sync};
                            left2 <= {shift2[30:0], d2_sync};
                            left3 <= {shift3[30:0], d3_sync};
                        end else begin
                            right0 <= {shift0[30:0], d0_sync};
                            right1 <= {shift1[30:0], d1_sync};
                            right2 <= {shift2[30:0], d2_sync};
                            right3 <= {shift3[30:0], d3_sync};
                        end
                    end else begin
                        bit_in_slot <= bit_in_slot + 1'b1;
                    end
                end else begin
                    // Falling BCK edge: change WS only between complete slots.
                    bck_reg <= 1'b0;
                    if (slot_done_pending) begin
                        slot_done_pending <= 1'b0;
                        if (ws_reg == 1'b0) begin
                            ws_reg <= 1'b1;
                        end else begin
                            ws_reg <= 1'b0;
                            frame_sync_pulse <= 1'b1;
                            if (frame_ready || out_active) begin
                                error_flag <= 1'b1;
                                error_count <= error_count + 1'b1;
                            end else begin
                                // D3 left is the documented empty slot; ch7 is
                                // deliberately driven to zero, never stale data.
                                frame_ch0 <= $signed(left0[31:16]);
                                frame_ch1 <= $signed(right0[31:16]);
                                frame_ch2 <= $signed(left1[31:16]);
                                frame_ch3 <= $signed(right1[31:16]);
                                frame_ch4 <= $signed(left2[31:16]);
                                frame_ch5 <= $signed(right2[31:16]);
                                frame_ch6 <= $signed(right3[31:16]);
                                frame_ch7 <= 16'sd0;
                                pending_sample_index <= sample_index;
                                pending_frame_index <= frame_index;
                                frame_ready <= 1'b1;
                                if (sample_index == SAMPLES_PER_FRAME - 1) begin
                                    sample_index <= {SAMPLE_INDEX_W{1'b0}};
                                    frame_index <= frame_index + 1'b1;
                                end else begin
                                    sample_index <= sample_index + 1'b1;
                                end
                            end
                        end
                    end
                end
            end else begin
                div_count <= div_count + 1'b1;
            end
        end
    end

    initial begin
        if (SAMPLES_PER_FRAME < 1) $error("SAMPLES_PER_FRAME must be positive");
        if (BCK_HALF_DIV < 1) $error("BCK_HALF_DIV must be positive");
    end
endmodule
