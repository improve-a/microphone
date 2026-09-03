`timescale 1ns/1ps

module tb_lc_ai_k210_7mic_frontend;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg [31:0] slot;
    reg signed [23:0] raw24;
    reg signed [15:0] actual;

    always #5 clk = ~clk;

    lc_ai_k210_7mic_frontend #(.PCM_RIGHT_SHIFT(8)) dut_shift8 (
        .clk(clk), .resetn(resetn),
        .mic_d0(1'b0), .mic_d1(1'b0), .mic_d2(1'b0), .mic_d3(1'b0),
        .mic_bck(), .mic_ws(), .pcm_data_o(), .pcm_valid_o(),
        .pcm_ready_i(1'b1), .pcm_last_o(), .channel_index_o(),
        .sample_index_o(), .frame_index_o(), .debug_probe_o()
    );

    lc_ai_k210_7mic_frontend #(.PCM_RIGHT_SHIFT(0)) dut_shift0 (
        .clk(clk), .resetn(resetn),
        .mic_d0(1'b0), .mic_d1(1'b0), .mic_d2(1'b0), .mic_d3(1'b0),
        .mic_bck(), .mic_ws(), .pcm_data_o(), .pcm_valid_o(),
        .pcm_ready_i(1'b1), .pcm_last_o(), .channel_index_o(),
        .sample_index_o(), .frame_index_o(), .debug_probe_o()
    );

    task check_shift8(input signed [23:0] sample, input signed [15:0] expected);
        begin
            raw24 = sample;
            slot = {1'b1, raw24, 7'b0};
            actual = dut_shift8.pcm16_from_slot(slot);
            if (actual !== expected) begin
                $display("MIC_I2S_SCALE_FAIL raw=%h actual=%h expected=%h", raw24, actual, expected);
                $fatal(1);
            end
        end
    endtask

    initial begin
        #20;
        // slot[31] deliberately differs from the true sign bit. A correct
        // delayed-I2S decoder must ignore it and use slot[30].
        check_shift8(24'sh123400, 16'sh1234);
        check_shift8(-24'sh123400, -16'sh1234);
        check_shift8(24'sh7fffff, 16'sh7fff);
        check_shift8(-24'sh800000, -16'sh8000);

        raw24 = 24'sh010000;
        slot = {1'b0, raw24, 7'b0};
        actual = dut_shift0.pcm16_from_slot(slot);
        if (actual !== 16'sh7fff) $fatal(1, "positive saturation failed");
        raw24 = -24'sh010000;
        slot = {1'b1, raw24, 7'b0};
        actual = dut_shift0.pcm16_from_slot(slot);
        if (actual !== -16'sh8000) $fatal(1, "negative saturation failed");

        $display("MIC_I2S_SCALE_RTL_PASS");
        $finish;
    end
endmodule
