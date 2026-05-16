`timescale 1ns / 1ps

module conv2_pin2_pout6_pk1_tb;

    reg clk;
    reg rstn;
    reg start;

    reg fmap_valid;
    reg signed [7:0] fmap_0;
    reg signed [7:0] fmap_1;

    reg signed [7:0] weight;
    reg [5:0] weight_en;

    wire ovalid;
    wire done;
    wire signed [31:0] dout_0;
    wire signed [31:0] dout_1;
    wire signed [31:0] dout_2;
    wire signed [31:0] dout_3;
    wire signed [31:0] dout_4;
    wire signed [31:0] dout_5;

    reg signed [7:0] fmap0_mem [0:143];
    reg signed [7:0] fmap1_mem [0:143];
    reg signed [7:0] w0_mem [0:49];
    reg signed [7:0] w1_mem [0:49];
    reg signed [7:0] w2_mem [0:49];
    reg signed [7:0] w3_mem [0:49];
    reg signed [7:0] w4_mem [0:49];
    reg signed [7:0] w5_mem [0:49];

    integer i;
    integer bank_idx;
    integer out_count;
    integer err_count;
    reg done_seen;

    localparam integer CLK_PERIOD_NS = 20;
    localparam integer TIMEOUT_NS = 200000;

    conv2_pin2_pout6_pk1 dut (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .fmap_valid(fmap_valid),
        .fmap_0(fmap_0),
        .fmap_1(fmap_1),
        .weight(weight),
        .weight_en(weight_en),
        .ovalid(ovalid),
        .done(done),
        .dout_0(dout_0),
        .dout_1(dout_1),
        .dout_2(dout_2),
        .dout_3(dout_3),
        .dout_4(dout_4),
        .dout_5(dout_5)
    );

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    function signed [31:0] calc_expected;
        input integer out_id;
        input integer ch_id;
        integer tap;
        integer out_row;
        integer out_col;
        integer tap_row;
        integer tap_col;
        integer idx;
        integer sum;
        begin
            sum = 0;
            out_row = out_id / 8;
            out_col = out_id % 8;

            for (tap = 0; tap < 25; tap = tap + 1) begin
                tap_row = tap / 5;
                tap_col = tap % 5;
                idx = (out_row + tap_row) * 12 + out_col + tap_col;

                case (ch_id)
                    0: sum = sum + fmap0_mem[idx] * w0_mem[tap] + fmap1_mem[idx] * w0_mem[tap + 25];
                    1: sum = sum + fmap0_mem[idx] * w1_mem[tap] + fmap1_mem[idx] * w1_mem[tap + 25];
                    2: sum = sum + fmap0_mem[idx] * w2_mem[tap] + fmap1_mem[idx] * w2_mem[tap + 25];
                    3: sum = sum + fmap0_mem[idx] * w3_mem[tap] + fmap1_mem[idx] * w3_mem[tap + 25];
                    4: sum = sum + fmap0_mem[idx] * w4_mem[tap] + fmap1_mem[idx] * w4_mem[tap + 25];
                    5: sum = sum + fmap0_mem[idx] * w5_mem[tap] + fmap1_mem[idx] * w5_mem[tap + 25];
                    default: sum = sum;
                endcase
            end

            calc_expected = sum;
        end
    endfunction

    task drive_weight_one_cycle;
        input integer bank;
        input integer idx;
        begin
            @(negedge clk);
            case (bank)
                0: begin weight <= w0_mem[idx]; weight_en <= 6'b000001; end
                1: begin weight <= w1_mem[idx]; weight_en <= 6'b000010; end
                2: begin weight <= w2_mem[idx]; weight_en <= 6'b000100; end
                3: begin weight <= w3_mem[idx]; weight_en <= 6'b001000; end
                4: begin weight <= w4_mem[idx]; weight_en <= 6'b010000; end
                5: begin weight <= w5_mem[idx]; weight_en <= 6'b100000; end
                default: begin weight <= 8'sd0; weight_en <= 6'b000000; end
            endcase
        end
    endtask

    task clear_weight_bus;
        begin
            @(negedge clk);
            weight <= 8'sd0;
            weight_en <= 6'b000000;
        end
    endtask

    task drive_fmap_one_cycle;
        input integer idx;
        begin
            @(negedge clk);
            fmap_valid <= 1'b1;
            fmap_0 <= fmap0_mem[idx];
            fmap_1 <= fmap1_mem[idx];
        end
    endtask

    task clear_fmap_bus;
        begin
            @(negedge clk);
            fmap_valid <= 1'b0;
            fmap_0 <= 8'sd0;
            fmap_1 <= 8'sd0;
        end
    endtask

    task check_output;
        input integer out_id;
        reg signed [31:0] exp0;
        reg signed [31:0] exp1;
        reg signed [31:0] exp2;
        reg signed [31:0] exp3;
        reg signed [31:0] exp4;
        reg signed [31:0] exp5;
        begin
            exp0 = calc_expected(out_id, 0);
            exp1 = calc_expected(out_id, 1);
            exp2 = calc_expected(out_id, 2);
            exp3 = calc_expected(out_id, 3);
            exp4 = calc_expected(out_id, 4);
            exp5 = calc_expected(out_id, 5);

            if (($signed(dout_0) !== exp0) ||
                ($signed(dout_1) !== exp1) ||
                ($signed(dout_2) !== exp2) ||
                ($signed(dout_3) !== exp3) ||
                ($signed(dout_4) !== exp4) ||
                ($signed(dout_5) !== exp5)) begin
                err_count = err_count + 1;
                $display("MISMATCH out=%0d time=%0t", out_id, $time);
                $display("  ch0 dut=%0d exp=%0d", $signed(dout_0), exp0);
                $display("  ch1 dut=%0d exp=%0d", $signed(dout_1), exp1);
                $display("  ch2 dut=%0d exp=%0d", $signed(dout_2), exp2);
                $display("  ch3 dut=%0d exp=%0d", $signed(dout_3), exp3);
                $display("  ch4 dut=%0d exp=%0d", $signed(dout_4), exp4);
                $display("  ch5 dut=%0d exp=%0d", $signed(dout_5), exp5);
            end
        end
    endtask

    always @(posedge clk) begin
        if (ovalid) begin
            check_output(out_count);
            out_count = out_count + 1;
        end

        if (done) begin
            done_seen = 1'b1;
            $display("done asserted at time=%0t, out_count=%0d, err_count=%0d", $time, out_count, err_count);
        end
    end

    initial begin
        clk = 1'b0;
        rstn = 1'b0;
        start = 1'b0;
        fmap_valid = 1'b0;
        fmap_0 = 8'sd0;
        fmap_1 = 8'sd0;
        weight = 8'sd0;
        weight_en = 6'b000000;
        out_count = 0;
        err_count = 0;
        done_seen = 1'b0;

        for (i = 0; i < 144; i = i + 1) begin
            fmap0_mem[i] = (i % 13) - 6;
            fmap1_mem[i] = (i % 9) - 4;
        end

        for (i = 0; i < 50; i = i + 1) begin
            w0_mem[i] = (i % 5) - 2;
            w1_mem[i] = (i % 7) - 3;
            w2_mem[i] = (i % 4) - 1;
            w3_mem[i] = (i % 6) - 2;
            w4_mem[i] = (i % 3) - 1;
            w5_mem[i] = (i % 8) - 4;
        end

        repeat (4) @(posedge clk);
        rstn = 1'b1;
        repeat (2) @(posedge clk);
        start = 1'b1;

        for (bank_idx = 0; bank_idx < 6; bank_idx = bank_idx + 1) begin
            for (i = 0; i < 50; i = i + 1) begin
                drive_weight_one_cycle(bank_idx, i);
                clear_weight_bus();
            end
        end

        for (i = 0; i < 144; i = i + 1) begin
            drive_fmap_one_cycle(i);
            clear_fmap_bus();
        end

        wait(done_seen == 1'b1);
        repeat (5) @(posedge clk);

        if (out_count != 64) begin
            $display("FAIL: expected 64 outputs, got %0d", out_count);
            err_count = err_count + 1;
        end

        if (err_count == 0)
            $display("TB PASS");
        else
            $display("TB FAIL, err_count=%0d", err_count);

        $finish;
    end

    initial begin
        #TIMEOUT_NS;
        $display("TIMEOUT at %0t, out_count=%0d, done_seen=%0d", $time, out_count, done_seen);
        $finish;
    end

endmodule
