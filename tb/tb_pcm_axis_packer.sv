`timescale 1ns/1ps

module tb_pcm_axis_packer;
    reg clk=0, resetn=0;
    reg signed [15:0] pcm_data=0;
    reg pcm_valid=0, pcm_last=0;
    wire pcm_ready;
    wire [31:0] tdata;
    wire [3:0] tkeep;
    wire tvalid, tlast;
    reg tready=0;
    integer output_count=0;

    pcm_axis_packer dut(
        .clk(clk), .resetn(resetn), .pcm_data_i(pcm_data), .pcm_valid_i(pcm_valid),
        .pcm_ready_o(pcm_ready), .pcm_last_i(pcm_last), .m_axis_tdata(tdata),
        .m_axis_tkeep(tkeep), .m_axis_tvalid(tvalid), .m_axis_tready(tready),
        .m_axis_tlast(tlast)
    );
    always #5 clk=~clk;

    task automatic send(input signed [15:0] value, input is_last);
        begin
            @(negedge clk); pcm_data=value; pcm_last=is_last; pcm_valid=1;
            while (!pcm_ready) @(negedge clk);
            @(posedge clk); @(negedge clk); pcm_valid=0; pcm_last=0;
        end
    endtask

    always @(posedge clk) begin
        if (tvalid && tready) begin
            case (output_count)
                0: if (tdata!==32'h80000001 || tkeep!==4'hF || tlast) $fatal(1,"word0");
                1: if (tdata!==32'h00007FFF || tkeep!==4'h3 || !tlast) $fatal(1,"word1");
                default: $fatal(1,"extra output");
            endcase
            output_count=output_count+1;
        end
    end

    initial begin
        repeat(3) @(posedge clk); resetn=1; tready=1;
        send(16'sd1,0); send(-16'sd32768,0);
        while (output_count < 1) @(negedge clk);
        tready=0; send(16'sd32767,1);
        repeat(4) @(posedge clk);
        if (!tvalid || tdata!==32'h00007FFF) $fatal(1,"backpressure stability");
        @(negedge clk); tready=1;
        repeat(3) @(posedge clk);
        @(negedge clk);
        if (output_count!=2) $display("MIC_PACKER_RTL_FAIL output_count=%0d",output_count);
        else $display("MIC_PACKER_RTL_PASS");
        $finish;
    end
endmodule
