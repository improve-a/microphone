`timescale 1ns/1ps

module tb_pcm_synthetic_source;
    localparam integer CHANNELS = 8;
    localparam integer SAMPLES = 16;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg mode = 1'b0;
    reg [31:0] seed = 32'h13579BDF;
    reg ready = 1'b0;
    wire signed [15:0] data;
    wire valid, last;
    wire [2:0] channel_index;
    wire [3:0] sample_index;
    wire [31:0] frame_index;

    pcm_synthetic_source #(
        .CHANNELS(CHANNELS),
        .SAMPLES_PER_FRAME(SAMPLES)
    ) dut (
        .clk(clk), .resetn(resetn), .mode_i(mode), .seed_i(seed),
        .pcm_data_o(data), .pcm_valid_o(valid), .pcm_ready_i(ready),
        .pcm_last_o(last), .channel_index_o(channel_index),
        .sample_index_o(sample_index), .frame_index_o(frame_index)
    );

    always #5 clk = ~clk;

    function automatic signed [15:0] sine_q15(input [4:0] phase);
        begin
            case (phase)
                0:sine_q15=0; 1:sine_q15=6393; 2:sine_q15=12539; 3:sine_q15=18204;
                4:sine_q15=23170; 5:sine_q15=27245; 6:sine_q15=30273; 7:sine_q15=32137;
                8:sine_q15=32767; 9:sine_q15=32137; 10:sine_q15=30273; 11:sine_q15=27245;
                12:sine_q15=23170; 13:sine_q15=18204; 14:sine_q15=12539; 15:sine_q15=6393;
                16:sine_q15=0; 17:sine_q15=-6393; 18:sine_q15=-12539; 19:sine_q15=-18204;
                20:sine_q15=-23170; 21:sine_q15=-27245; 22:sine_q15=-30273; 23:sine_q15=-32137;
                24:sine_q15=-32768; 25:sine_q15=-32137; 26:sine_q15=-30273; 27:sine_q15=-27245;
                28:sine_q15=-23170; 29:sine_q15=-18204; 30:sine_q15=-12539; default:sine_q15=-6393;
            endcase
        end
    endfunction

    function automatic signed [15:0] expected_sample(
        input integer f, input integer s, input integer c, input integer selected_mode
    );
        reg [31:0] idx, x;
        reg signed [15:0] raw;
        begin
            if (s < c) expected_sample = 0;
            else begin
                idx = f * SAMPLES + s - c;
                if (selected_mode == 0) raw = sine_q15(idx[4:0]);
                else begin
                    x = idx ^ seed; x = x ^ (x << 13); x = x ^ (x >> 17); x = x ^ (x << 5);
                    raw = x[15:0];
                end
                expected_sample = raw >>> ((c > 15) ? 15 : c);
            end
        end
    endfunction

    task automatic run_mode(input integer selected_mode);
        integer accepted, cycles, expected_f, expected_s, expected_c;
        reg stalled;
        reg signed [15:0] held_data;
        reg held_last;
        reg [2:0] held_channel;
        reg [3:0] held_sample;
        reg [31:0] held_frame;
        begin
            mode = selected_mode;
            resetn = 0; ready = 0; repeat (3) @(posedge clk);
            if (valid !== 0) $fatal(1, "valid asserted during reset");
            resetn = 1;
            accepted=0; cycles=0; expected_f=0; expected_s=0; expected_c=0; stalled=0;
            while (accepted < 2*CHANNELS*SAMPLES) begin
                @(negedge clk);
                ready = ((cycles % 7) != 1) && ((cycles % 11) != 4);
                if (stalled) begin
                    if (data !== held_data || last !== held_last || channel_index !== held_channel ||
                        sample_index !== held_sample || frame_index !== held_frame)
                        $fatal(1, "output changed while stalled");
                end
                if (valid) begin
                    if (channel_index !== expected_c || sample_index !== expected_s || frame_index !== expected_f)
                        $fatal(1, "metadata mismatch mode=%0d beat=%0d", selected_mode, accepted);
                    if (data !== expected_sample(expected_f, expected_s, expected_c, selected_mode))
                        $fatal(1, "sample mismatch mode=%0d f=%0d s=%0d c=%0d got=%0d",
                            selected_mode, expected_f, expected_s, expected_c, data);
                    if (last !== ((expected_c==CHANNELS-1) && (expected_s==SAMPLES-1)))
                        $fatal(1, "TLAST mismatch");
                end
                stalled = valid && !ready;
                held_data=data; held_last=last; held_channel=channel_index;
                held_sample=sample_index; held_frame=frame_index;
                if (valid && ready) begin
                    accepted = accepted + 1;
                    if (expected_c == CHANNELS-1) begin
                        expected_c = 0;
                        if (expected_s == SAMPLES-1) begin expected_s=0; expected_f=expected_f+1; end
                        else expected_s=expected_s+1;
                    end else expected_c=expected_c+1;
                end
                cycles=cycles+1;
                if (cycles > 2000) $fatal(1, "timeout");
            end
            ready = 0;
        end
    endtask

    initial begin
        run_mode(0);
        run_mode(1);
        $display("MIC_FRONTEND_RTL_PASS");
        $finish;
    end
endmodule

